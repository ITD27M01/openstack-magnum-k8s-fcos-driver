# Copyright 2016 Rackspace Inc. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License"); you may
# not use this file except in compliance with the License. You may obtain
# a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
# WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
# License for the specific language governing permissions and limitations
# under the License.
import os
import json

from oslo_log import log as logging
from oslo_utils import strutils


import magnum.conf
from magnum.common import cinder
from magnum.common import exception
from magnum.common.x509 import operations as x509
from magnum.conductor.handlers.common import cert_manager
from magnum.drivers.heat import k8s_template_def
from magnum.i18n import _
import six

CONF = magnum.conf.CONF

LOG = logging.getLogger(__name__)

PODS_NETWORK_CIDR = '10.100.0.0/16'
LABEL_LIST = ['coredns_tag',
              'kube_tag',
              'hyperkube_prefix',
              'container_infra_prefix',
              'container_infra_proxy',
              'availability_zone',
              'cgroup_driver',
              'container_runtime',
              'containerd_version',
              'containerd_tarball_url',
              'containerd_tarball_sha256',
              'calico_tag',
              'calico_kube_controllers_tag',
              'calico_ipv4pool',
              'calico_ipv4pool_ipip',
              'cinder_csi_enabled',
              'cinder_csi_plugin_tag',
              'csi_attacher_tag',
              'csi_provisioner_tag',
              'csi_snapshotter_tag',
              'csi_resizer_tag',
              'csi_node_driver_registrar_tag',
              'etcd_tag',
              'flannel_tag',
              'flannel_cni_tag',
              'cloud_provider_tag',
              'heat_container_agent_tag',
              'keystone_auth_enabled',
              'k8s_keystone_auth_tag',
              'selinux_mode',
              'node_problem_detector_tag',
              'auto_healing_enabled',
              'auto_scaling_enabled',
              'auto_healing_controller',
              'magnum_auto_healer_tag',
              'draino_tag',
              'autoscaler_tag',
              'min_node_count', 'max_node_count', 'npd_enabled',
              'ostree_remote', 'ostree_commit',
              'use_podman', 'kube_image_digest']

ENV_PATH = "heat_resources/environments/"


class FCOSK8sTemplateDefinition(k8s_template_def.K8sTemplateDefinition):
    """Kubernetes template for a Fedora."""

    def __init__(self):
        super(FCOSK8sTemplateDefinition, self).__init__()
        self.add_parameter('docker_storage_driver',
                           cluster_template_attr='docker_storage_driver')

    def get_params(self, context, cluster_template, cluster, **kwargs):
        extra_params = kwargs.pop('extra_params', {})

        extra_params['username'] = context.user_name
        osc = self.get_osc(context)
        extra_params['region_name'] = osc.cinder_region_name()

        self._set_volumes(context, cluster, extra_params)

        extra_params['nodes_affinity_policy'] = \
            CONF.cluster.nodes_affinity_policy

        if cluster_template.network_driver == 'flannel':
            extra_params["pods_network_cidr"] = \
                cluster.labels.get('flannel_network_cidr', PODS_NETWORK_CIDR)
        if cluster_template.network_driver == 'calico':
            extra_params["pods_network_cidr"] = \
                cluster.labels.get('calico_ipv4pool', PODS_NETWORK_CIDR)

        # check cloud provider and cinder options. If cinder is selected,
        # the cloud provider needs to be enabled.
        cloud_provider_enabled = cluster.labels.get(
            'cloud_provider_enabled',
            'true' if CONF.trust.cluster_user_trust else 'false')
        if (not CONF.trust.cluster_user_trust
                and cloud_provider_enabled.lower() == 'true'):
            raise exception.InvalidParameterValue(_(
                '"cluster_user_trust" must be set to True in magnum.conf when '
                '"cloud_provider_enabled" label is set to true.'))
        if (cluster_template.volume_driver == 'cinder'
                and cloud_provider_enabled.lower() == 'false'):
            raise exception.InvalidParameterValue(_(
                '"cinder" volume driver needs "cloud_provider_enabled" label '
                'to be true or unset.'))
        extra_params['cloud_provider_enabled'] = cloud_provider_enabled

        label_list = LABEL_LIST

        labels = self._get_relevant_labels(cluster, kwargs)

        for label in label_list:
            label_value = labels.get(label)
            if label_value:
                extra_params[label] = label_value

        csr_keys = x509.generate_csr_and_key(u"Kubernetes Service Account")

        extra_params['kube_service_account_key'] = \
            csr_keys["public_key"].replace("\n", "\\n")
        extra_params['kube_service_account_private_key'] = \
            csr_keys["private_key"].replace("\n", "\\n")

        extra_params['project_id'] = cluster.project_id
        extra_params['post_install_manifest_url'] = \
            CONF.kubernetes.post_install_manifest_url

        if not extra_params.get('max_node_count'):
            extra_params['max_node_count'] = cluster.node_count + 1

        self._set_cert_manager_params(context, cluster, extra_params)
        self._get_keystone_auth_default_policy(extra_params)
        self._set_volumes(context, cluster, extra_params)

        return super(FCOSK8sTemplateDefinition,
                     self).get_params(context, cluster_template, cluster,
                                      extra_params=extra_params,
                                      **kwargs)

    def _set_cert_manager_params(self, context, cluster, extra_params):
        cert_manager_api = cluster.labels.get('cert_manager_api')
        if strutils.bool_from_string(cert_manager_api):
            extra_params['cert_manager_api'] = cert_manager_api
            ca_cert = cert_manager.get_cluster_ca_certificate(cluster,
                                                              context=context)
            if six.PY3 and isinstance(ca_cert.get_private_key_passphrase(),
                                      six.text_type):
                extra_params['ca_key'] = x509.decrypt_key(
                    ca_cert.get_private_key(),
                    ca_cert.get_private_key_passphrase().encode()
                ).decode().replace("\n", "\\n")
            else:
                extra_params['ca_key'] = x509.decrypt_key(
                    ca_cert.get_private_key(),
                    ca_cert.get_private_key_passphrase()).replace("\n", "\\n")

    def _get_keystone_auth_default_policy(self, extra_params):
        # NOTE(flwang): This purpose of this function is to make the default
        # policy more flexible for different cloud providers. Since the default
        # policy was "hardcode" in the bash script and vendors can't change
        # it unless fork it. So the new config option is introduced to address
        # this. This function can be extracted to k8s_template_def.py if k8s
        # keystone auth feature is adopted by other drivers.

        default_policy = """[{"resource": {"verbs": ["list"],
            "resources": ["pods", "services", "deployments", "pvc"],
            "version": "*", "namespace": "default"},
            "match": [{"type": "role","values": ["member"]},
            {"type": "project", "values": ["$PROJECT_ID"]}]}]"""

        keystone_auth_enabled = extra_params.get("keystone_auth_enabled",
                                                 "True")
        if strutils.bool_from_string(keystone_auth_enabled):
            try:
                with open(CONF.kubernetes.keystone_auth_default_policy) as f:
                    default_policy = json.dumps(json.loads(f.read()))
            except Exception:
                LOG.error("Failed to load default keystone auth policy")
                default_policy = json.dumps(json.loads(default_policy),
                                            sort_keys=True)

            washed_policy = default_policy.replace('"', '\"') \
                .replace("$PROJECT_ID", extra_params["project_id"])
            extra_params["keystone_auth_default_policy"] = washed_policy

    def _set_volumes(self, context, cluster, extra_params):
        # set docker_volume_type
        docker_volume_size = cluster.docker_volume_size or 0
        docker_volume_type = (cluster.labels.get(
            'docker_volume_type',
            cinder.get_default_docker_volume_type(context))
                              if int(docker_volume_size) > 0 else '')
        extra_params['docker_volume_type'] = docker_volume_type

        # set etcd_volume_type
        etcd_volume_size = cluster.labels.get('etcd_volume_size', 0)
        etcd_volume_type = (cluster.labels.get(
            'etcd_volume_type',
            cinder.get_default_etcd_volume_type(context))
                            if int(etcd_volume_size) > 0 else '')
        extra_params['etcd_volume_type'] = etcd_volume_type

        # set boot_volume_size
        boot_volume_size = cluster.labels.get(
            'boot_volume_size', CONF.cinder.default_boot_volume_size)
        extra_params['boot_volume_size'] = boot_volume_size

        # set boot_volume_type
        boot_volume_type = (cluster.labels.get(
            'boot_volume_type',
            cinder.get_default_boot_volume_type(context))
                            if int(boot_volume_size) > 0 else '')
        extra_params['boot_volume_type'] = boot_volume_type

    def get_env_files(self, cluster_template, cluster, nodegroup=None):
        env_files = []

        # TODO(igortiunov): split this to method someday
        # Private Network
        if cluster.fixed_network or cluster_template.fixed_network:
            env_files.append(ENV_PATH + 'no_private_network.yaml')
        else:
            env_files.append(ENV_PATH + 'with_private_network.yaml')

        # ETCD volume
        if int(cluster.labels.get('etcd_volume_size', 0)) > 0:
            env_files.append(ENV_PATH + 'with_etcd_volume.yaml')
        else:
            env_files.append(ENV_PATH + 'no_etcd_volume.yaml')

        # External volume for image storage
        if nodegroup:
            docker_volume_size = nodegroup.docker_volume_size
        else:
            docker_volume_size = cluster.docker_volume_size
        if docker_volume_size is None:
            env_files.append(ENV_PATH + 'no_volume.yaml')
        else:
            env_files.append(ENV_PATH + 'with_volume.yaml')

        # LoadBalancer
        if cluster_template.master_lb_enabled:
            env_files.append(ENV_PATH + 'with_master_lb_octavia.yaml')
        else:
            env_files.append(ENV_PATH + 'no_master_lb.yaml')

        # Floating IPs
        lb_fip_enabled = cluster.labels.get("master_lb_floating_ip_enabled")
        master_lb_fip_enabled = (strutils.bool_from_string(lb_fip_enabled) or
                                 cluster.floating_ip_enabled)

        if cluster.floating_ip_enabled:
            env_files.append(ENV_PATH + 'enable_floating_ip.yaml')
        else:
            env_files.append(ENV_PATH + 'disable_floating_ip.yaml')

        if cluster_template.master_lb_enabled and master_lb_fip_enabled:
            env_files.append(ENV_PATH + 'enable_lb_floating_ip.yaml')
        else:
            env_files.append(ENV_PATH + 'disable_lb_floating_ip.yaml')

        return env_files

    @property
    def driver_module_path(self):
        return __name__[:__name__.rindex('.')]

    @property
    def template_path(self):
        return os.path.join(os.path.dirname(os.path.realpath(__file__)),
                            'templates/kubecluster.yaml')
