echo "START: write-heat-params"

arch=$(uname -m)

case "$arch" in
    aarch64)
        ARCH=arm64
        ;;
    x86_64)
        ARCH=amd64
        ;;
    *)
        ARCH=$arch
        ;;
esac

HEAT_PARAMS=/etc/sysconfig/heat-params
[ -f ${HEAT_PARAMS} ] || {
    echo "Writing File: $HEAT_PARAMS"
    mkdir -p "$(dirname ${HEAT_PARAMS})"
    cat > ${HEAT_PARAMS} <<EOF
ARCH="$ARCH"
INSTANCE_NAME="$INSTANCE_NAME"
KUBE_API_PUBLIC_ADDRESS="$KUBE_API_PUBLIC_ADDRESS"
KUBE_API_PRIVATE_ADDRESS="$KUBE_API_PRIVATE_ADDRESS"
KUBE_API_PORT="$KUBE_API_PORT"
KUBE_NODE_PUBLIC_IP="$KUBE_NODE_PUBLIC_IP"
KUBE_NODE_IP="$KUBE_NODE_IP"
KUBE_ALLOW_PRIV="$KUBE_ALLOW_PRIV"
ENABLE_CINDER="$ENABLE_CINDER"
ETCD_VOLUME="$ETCD_VOLUME"
ETCD_VOLUME_SIZE="$ETCD_VOLUME_SIZE"
DOCKER_VOLUME="$DOCKER_VOLUME"
DOCKER_VOLUME_SIZE="$DOCKER_VOLUME_SIZE"
DOCKER_STORAGE_DRIVER="$DOCKER_STORAGE_DRIVER"
CGROUP_DRIVER="$CGROUP_DRIVER"
NETWORK_DRIVER="$NETWORK_DRIVER"
FLANNEL_NETWORK_CIDR="$FLANNEL_NETWORK_CIDR"
FLANNEL_NETWORK_SUBNETLEN="$FLANNEL_NETWORK_SUBNETLEN"
FLANNEL_BACKEND="$FLANNEL_BACKEND"
PODS_NETWORK_CIDR="$PODS_NETWORK_CIDR"
PORTAL_NETWORK_CIDR="$PORTAL_NETWORK_CIDR"
ADMISSION_CONTROL_LIST="$ADMISSION_CONTROL_LIST"
ETCD_DISCOVERY_URL="$ETCD_DISCOVERY_URL"
USERNAME="$USERNAME"
PASSWORD="$PASSWORD"
CLUSTER_NETWORK="$CLUSTER_NETWORK"
CLUSTER_NETWORK_NAME="$CLUSTER_NETWORK_NAME"
CLUSTER_SUBNET="$CLUSTER_SUBNET"
TLS_DISABLED="False"
VERIFY_CA="$VERIFY_CA"
CLUSTER_UUID="$CLUSTER_UUID"
MAGNUM_URL="$MAGNUM_URL"
VOLUME_DRIVER="$VOLUME_DRIVER"
REGION_NAME="$REGION_NAME"
KUBE_TAG="$KUBE_TAG"
HYPERKUBE_PREFIX="$HYPERKUBE_PREFIX"
CLOUD_PROVIDER_TAG="$CLOUD_PROVIDER_TAG"
CLOUD_PROVIDER_ENABLED="$CLOUD_PROVIDER_ENABLED"
ETCD_TAG="$ETCD_TAG"
COREDNS_TAG="$COREDNS_TAG"
FLANNEL_TAG="$FLANNEL_TAG"
FLANNEL_CNI_TAG="$FLANNEL_CNI_TAG"
TRUSTEE_USER_ID="$TRUSTEE_USER_ID"
TRUSTEE_PASSWORD="$TRUSTEE_PASSWORD"
TRUST_ID="$TRUST_ID"
AUTH_URL="$AUTH_URL"
CONTAINER_INFRA_PREFIX="$CONTAINER_INFRA_PREFIX"
CONTAINER_INFRA_PROXY="$CONTAINER_INFRA_PROXY"
SYSTEM_PODS_INITIAL_DELAY="$SYSTEM_PODS_INITIAL_DELAY"
SYSTEM_PODS_TIMEOUT="$SYSTEM_PODS_TIMEOUT"
ETCD_LB_VIP="$ETCD_LB_VIP"
DNS_SERVICE_IP="$DNS_SERVICE_IP"
DNS_CLUSTER_DOMAIN="$DNS_CLUSTER_DOMAIN"
CALICO_TAG="$CALICO_TAG"
CALICO_KUBE_CONTROLLERS_TAG="$CALICO_KUBE_CONTROLLERS_TAG"
CALICO_IPV4POOL="$CALICO_IPV4POOL"
CALICO_IPV4POOL_IPIP="$CALICO_IPV4POOL_IPIP"
KUBELET_OPTIONS="$KUBELET_OPTIONS"
KUBECONTROLLER_OPTIONS="$KUBECONTROLLER_OPTIONS"
KUBEAPI_OPTIONS="$KUBEAPI_OPTIONS"
KUBEPROXY_OPTIONS="$KUBEPROXY_OPTIONS"
KUBESCHEDULER_OPTIONS="$KUBESCHEDULER_OPTIONS"
OCTAVIA_ENABLED="$OCTAVIA_ENABLED"
KUBE_SERVICE_ACCOUNT_KEY="$KUBE_SERVICE_ACCOUNT_KEY"
KUBE_SERVICE_ACCOUNT_PRIVATE_KEY="$KUBE_SERVICE_ACCOUNT_PRIVATE_KEY"
HEAT_CONTAINER_AGENT_TAG="$HEAT_CONTAINER_AGENT_TAG"
KEYSTONE_AUTH_ENABLED="$KEYSTONE_AUTH_ENABLED"
K8S_KEYSTONE_AUTH_TAG="$K8S_KEYSTONE_AUTH_TAG"
PROJECT_ID="$PROJECT_ID"
EXTERNAL_NETWORK_ID="$EXTERNAL_NETWORK_ID"
NODE_PROBLEM_DETECTOR_TAG="$NODE_PROBLEM_DETECTOR_TAG"
AUTO_HEALING_ENABLED="$AUTO_HEALING_ENABLED"
AUTO_HEALING_CONTROLLER="$AUTO_HEALING_CONTROLLER"
AUTO_SCALING_ENABLED="$AUTO_SCALING_ENABLED"
CINDER_CSI_ENABLED="$CINDER_CSI_ENABLED"
CINDER_CSI_PLUGIN_TAG="$CINDER_CSI_PLUGIN_TAG"
CSI_ATTACHER_TAG="$CSI_ATTACHER_TAG"
CSI_PROVISIONER_TAG="$CSI_PROVISIONER_TAG"
CSI_SNAPSHOTTER_TAG="$CSI_SNAPSHOTTER_TAG"
CSI_RESIZER_TAG="$CSI_RESIZER_TAG"
CSI_NODE_DRIVER_REGISTRAR_TAG="$CSI_NODE_DRIVER_REGISTRAR_TAG"
DRAINO_TAG="$DRAINO_TAG"
MAGNUM_AUTO_HEALER_TAG="$MAGNUM_AUTO_HEALER_TAG"
AUTOSCALER_TAG="$AUTOSCALER_TAG"
MIN_NODE_COUNT="$MIN_NODE_COUNT"
MAX_NODE_COUNT="$MAX_NODE_COUNT"
NPD_ENABLED="$NPD_ENABLED"
NODEGROUP_ROLE="$NODEGROUP_ROLE"
NODEGROUP_NAME="$NODEGROUP_NAME"
USE_PODMAN="$USE_PODMAN"
KUBE_IMAGE_DIGEST="$KUBE_IMAGE_DIGEST"
CONTAINER_RUNTIME="$CONTAINER_RUNTIME"
CONTAINERD_VERSION="$CONTAINERD_VERSION"
CONTAINERD_TARBALL_URL="$CONTAINERD_TARBALL_URL"
CONTAINERD_TARBALL_SHA256="$CONTAINERD_TARBALL_SHA256"
POST_INSTALL_MANIFEST_URL="$POST_INSTALL_MANIFEST_URL"
INFRA_DNS_ZONE="$INFRA_DNS_ZONE"
EOF
}

chown root:root "${HEAT_PARAMS}"
chmod 600 "${HEAT_PARAMS}"

echo "END: write-heat-params"
