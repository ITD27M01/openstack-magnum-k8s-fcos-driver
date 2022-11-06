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

from oslo_log import log as logging

from magnum.drivers.heat import driver
from k8s_fedora_coreos_t101 import template_def

LOG = logging.getLogger(__name__)


class Driver(driver.FedoraKubernetesDriver):

    @property
    def provides(self):
        return [
            {'server_type': 'vm',
             'os': 'fedora-coreos-t101',
             'coe': 'kubernetes'},
        ]

    def get_template_definition(self):
        return template_def.FCOSK8sTemplateDefinition()

    def get_nodegroup_extra_params(self, cluster, osc):
        network = osc.heat().resources.get(cluster.stack_id, 'network')
        secgroup = osc.heat().resources.get(cluster.stack_id,
                                            'secgroup_kube_minion')

        dns_zone = osc.heat().resources.get(cluster.stack_id,
                                            'infra_dns_zone')

        api_address = ""
        for output in osc.heat().stacks.get(cluster.stack_id).outputs:
            if output['output_key'] == 'api_address':
                api_address = output['output_value']
                break

        return {
            'existing_infra_dns_zone': dns_zone.attributes['name'],
            'existing_master_private_ip': api_address,
            'existing_security_group': secgroup.attributes['id'],
            'fixed_network': network.attributes['fixed_network'],
            'fixed_subnet': network.attributes['fixed_subnet'],
        }
