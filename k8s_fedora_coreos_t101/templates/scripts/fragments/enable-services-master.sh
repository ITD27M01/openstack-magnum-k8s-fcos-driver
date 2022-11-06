. /etc/sysconfig/heat-params

_set_prefix() {
    _prefix="$1"
    if [ "$CONTAINER_INFRA_PROXY" = "True" ] && [ -n "$CONTAINER_INFRA_PREFIX" ]; then
        _domain=$(echo $_prefix | sed -e 's|/.*$||')
        _prefix=${CONTAINER_INFRA_PREFIX}${_prefix#${_domain}/}
    else
        _prefix=${CONTAINER_INFRA_PREFIX:-$_prefix}
    fi
    echo $_prefix
}

ssh_cmd="ssh -F /srv/magnum/.ssh/config root@localhost"

# make sure we pick up any modified unit files
$ssh_cmd systemctl daemon-reload

echo "starting services"
if [ ${CONTAINER_RUNTIME} = "containerd"  ] ; then
    container_runtime_service="containerd"
else
    container_runtime_service="docker"
fi
for action in enable restart; do
    for service in etcd ${container_runtime_service} kube-apiserver kube-controller-manager kube-scheduler kubelet kube-proxy; do
        echo "$action service $service"
        $ssh_cmd systemctl $action $service
    done
done

# Label self as master
until  [ "ok" = "$(kubectl get --raw='/healthz')" ] && \
    kubectl patch node ${INSTANCE_NAME} \
        --patch '{"metadata": {"labels": {"node-role.kubernetes.io/master": ""}}}'
do
    echo "Trying to label master node with node-role.kubernetes.io/master=\"\""
    sleep 5s
done

if [ "$(echo $USE_PODMAN | tr '[:upper:]' '[:lower:]')" == "true" ]; then
    KUBE_DIGEST=$($ssh_cmd podman image inspect $(_set_prefix ${HYPERKUBE_PREFIX})hyperkube:${KUBE_TAG} --format "{{.Digest}}")
    if [ -n "${KUBE_IMAGE_DIGEST}"  ] && [ "${KUBE_IMAGE_DIGEST}" != "${KUBE_DIGEST}" ]; then
        printf "The sha256 ${KUBE_DIGEST} of current hyperkube image cannot match the given one: ${KUBE_IMAGE_DIGEST}."
        exit 1
    fi
fi
