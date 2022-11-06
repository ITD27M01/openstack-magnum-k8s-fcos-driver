#!/bin/sh

step="kube-apiserver-to-kubelet-role"
printf "Starting to run ${step}\n"

set +x
. /etc/sysconfig/heat-params
set -x

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

echo "Waiting for Kubernetes API..."
until  [ "ok" = "$(curl --silent http://127.0.0.1:8080/healthz)" ]
do
    sleep 5
done

cat <<EOF | kubectl apply --validate=false -f -
apiVersion: rbac.authorization.k8s.io/v1beta1
kind: ClusterRole
metadata:
  annotations:
    rbac.authorization.kubernetes.io/autoupdate: "true"
  labels:
    kubernetes.io/bootstrapping: rbac-defaults
  name: system:kube-apiserver-to-kubelet
rules:
  - apiGroups:
      - ""
    resources:
      - nodes/proxy
      - nodes/stats
      - nodes/log
      - nodes/spec
      - nodes/metrics
    verbs:
      - "*"
EOF

cat <<EOF | kubectl apply --validate=false -f -
apiVersion: rbac.authorization.k8s.io/v1beta1
kind: ClusterRoleBinding
metadata:
  name: system:kube-apiserver
  namespace: ""
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: system:kube-apiserver-to-kubelet
subjects:
  - apiGroup: rbac.authorization.k8s.io
    kind: User
    name: kubernetes
EOF

# Overrides for kube-controller-manager secure connection
cat <<EOF | kubectl apply --validate=false -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: system:kube-controller-manager
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: system:kube-controller-manager
subjects:
- apiGroup: rbac.authorization.k8s.io
  kind: User
  name: system:kube-controller-manager
- apiGroup: rbac.authorization.k8s.io
  kind: User
  name: kubernetes
EOF

# Create an admin user and give it the cluster role.
ADMIN_RBAC=/srv/magnum/kubernetes/kubernetes-admin-rbac.yaml

[ -f ${ADMIN_RBAC} ] || {
    echo "Writing File: $ADMIN_RBAC"
    mkdir -p $(dirname ${ADMIN_RBAC})
    cat << EOF > ${ADMIN_RBAC}
apiVersion: v1
kind: ServiceAccount
metadata:
  name: admin
  namespace: kube-system
---
apiVersion: rbac.authorization.k8s.io/v1beta1
kind: ClusterRoleBinding
metadata:
  name: admin
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
- kind: ServiceAccount
  name: admin
  namespace: kube-system
EOF
}
kubectl apply --validate=false -f ${ADMIN_RBAC}

POD_SECURITY_POLICIES=/srv/magnum/kubernetes/podsecuritypolicies.yaml
# Pod Security Policies
[ -f ${POD_SECURITY_POLICIES} ] || {
    echo "Writing File: $POD_SECURITY_POLICIES"
    mkdir -p $(dirname ${POD_SECURITY_POLICIES})
    cat > ${POD_SECURITY_POLICIES} <<EOF
---
apiVersion: policy/v1beta1
kind: PodSecurityPolicy
metadata:
  name: magnum.privileged
  annotations:
    kubernetes.io/description: 'privileged allows full unrestricted access to
      pod features, as if the PodSecurityPolicy controller was not enabled.'
    seccomp.security.alpha.kubernetes.io/allowedProfileNames: '*'
  labels:
    kubernetes.io/cluster-service: "true"
    addonmanager.kubernetes.io/mode: Reconcile
spec:
  privileged: true
  allowPrivilegeEscalation: true
  allowedCapabilities:
  - '*'
  volumes:
  - '*'
  hostNetwork: true
  hostPorts:
  - min: 0
    max: 65535
  hostIPC: true
  hostPID: true
  runAsUser:
    rule: 'RunAsAny'
  seLinux:
    rule: 'RunAsAny'
  supplementalGroups:
    rule: 'RunAsAny'
  fsGroup:
    rule: 'RunAsAny'
  readOnlyRootFilesystem: false
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: magnum:podsecuritypolicy:privileged
  labels:
    kubernetes.io/cluster-service: "true"
    addonmanager.kubernetes.io/mode: Reconcile
rules:
- apiGroups:
  - policy
  resourceNames:
  - magnum.privileged
  resources:
  - podsecuritypolicies
  verbs:
  - use
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: magnum:psp:privileged
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: magnum:podsecuritypolicy:privileged
subjects:
- apiGroup: rbac.authorization.k8s.io
  kind: Group
  name: system:authenticated
- apiGroup: rbac.authorization.k8s.io
  kind: Group
  name: system:serviceaccounts
- apiGroup: rbac.authorization.k8s.io
  kind: Group
  name: system:anonymous
EOF
}
kubectl apply -f ${POD_SECURITY_POLICIES}

# Add the openstack trustee as a secret under kube-system
kubectl -n kube-system create secret generic os-trustee \
    --from-literal=os-authURL=${AUTH_URL} \
    --from-literal=os-trustID=${TRUST_ID} \
    --from-literal=os-trusteeID=${TRUSTEE_USER_ID} \
    --from-literal=os-trusteePassword=${TRUSTEE_PASSWORD} \
    --from-literal=os-region=${REGION_NAME} \
    --from-file=os-certAuthority=/etc/kubernetes/ca-bundle.crt

#TODO: add heat variables for master count to determine leaderelect true/False ?
if [ "$(echo "${CLOUD_PROVIDER_ENABLED}" | tr '[:upper:]' '[:lower:]')" = "true" ]; then
    occm_image="$(_set_prefix 'docker.io/k8scloudprovider/')openstack-cloud-controller-manager:${CLOUD_PROVIDER_TAG}"
    OCCM=/srv/magnum/kubernetes/openstack-cloud-controller-manager.yaml

    [ -f ${OCCM} ] || {
        echo "Writing File: ${OCCM}"
        mkdir -p $(dirname ${OCCM})
        cat << EOF > ${OCCM}
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: cloud-controller-manager
  namespace: kube-system
---
apiVersion: v1
items:
- apiVersion: rbac.authorization.k8s.io/v1
  kind: ClusterRole
  metadata:
    name: system:cloud-controller-manager
  rules:
  - apiGroups:
    - ""
    resources:
    - events
    verbs:
    - create
    - patch
    - update
  - apiGroups:
    - ""
    resources:
    - nodes
    verbs:
    - '*'
  - apiGroups:
    - ""
    resources:
    - nodes/status
    verbs:
    - patch
  - apiGroups:
    - ""
    resources:
    - services
    verbs:
    - list
    - patch
    - update
    - watch
  - apiGroups:
    - ""
    resources:
    - serviceaccounts
    verbs:
    - create
    - get
  - apiGroups:
    - ""
    resources:
    - persistentvolumes
    verbs:
    - '*'
  - apiGroups:
    - ""
    resources:
    - endpoints
    verbs:
    - create
    - get
    - list
    - watch
    - update
  - apiGroups:
    - ""
    resources:
    - configmaps
    verbs:
    - get
    - list
    - watch
  - apiGroups:
    - ""
    resources:
    - secrets
    verbs:
    - list
    - get
    - watch
  - apiGroups:
    - "coordination.k8s.io"
    resources:
    - leases
    verbs:
    - get
    - create
    - update
- apiVersion: rbac.authorization.k8s.io/v1
  kind: ClusterRole
  metadata:
    name: system:cloud-node-controller
  rules:
  - apiGroups:
    - ""
    resources:
    - nodes
    verbs:
    - '*'
  - apiGroups:
    - ""
    resources:
    - nodes/status
    verbs:
    - patch
  - apiGroups:
    - ""
    resources:
    - events
    verbs:
    - create
    - patch
    - update
- apiVersion: rbac.authorization.k8s.io/v1
  kind: ClusterRole
  metadata:
    name: system:pvl-controller
  rules:
  - apiGroups:
    - ""
    resources:
    - persistentvolumes
    verbs:
    - '*'
  - apiGroups:
    - ""
    resources:
    - events
    verbs:
    - create
    - patch
    - update
kind: List
metadata: {}
---
apiVersion: v1
items:
- apiVersion: rbac.authorization.k8s.io/v1
  kind: ClusterRoleBinding
  metadata:
    name: system:cloud-node-controller
  roleRef:
    apiGroup: rbac.authorization.k8s.io
    kind: ClusterRole
    name: system:cloud-node-controller
  subjects:
  - kind: ServiceAccount
    name: cloud-node-controller
    namespace: kube-system
- apiVersion: rbac.authorization.k8s.io/v1
  kind: ClusterRoleBinding
  metadata:
    name: system:pvl-controller
  roleRef:
    apiGroup: rbac.authorization.k8s.io
    kind: ClusterRole
    name: system:pvl-controller
  subjects:
  - kind: ServiceAccount
    name: pvl-controller
    namespace: kube-system
- apiVersion: rbac.authorization.k8s.io/v1
  kind: ClusterRoleBinding
  metadata:
    name: system:cloud-controller-manager
  roleRef:
    apiGroup: rbac.authorization.k8s.io
    kind: ClusterRole
    name: system:cloud-controller-manager
  subjects:
  - kind: ServiceAccount
    name: cloud-controller-manager
    namespace: kube-system
kind: List
metadata: {}
---
apiVersion: apps/v1
kind: DaemonSet
metadata:
  labels:
    k8s-app: openstack-cloud-controller-manager
  name: openstack-cloud-controller-manager
  namespace: kube-system
spec:
  selector:
    matchLabels:
      k8s-app: openstack-cloud-controller-manager
  template:
    metadata:
      labels:
        k8s-app: openstack-cloud-controller-manager
    spec:
      hostNetwork: true
      serviceAccountName: cloud-controller-manager
      containers:
      - name: openstack-cloud-controller-manager
        image: ${occm_image}
        command:
        - /bin/openstack-cloud-controller-manager
        - --v=2
        - --cloud-config=/etc/kubernetes/cloud-config-occm
        - --cluster-name=${CLUSTER_UUID}
        - --use-service-account-credentials=true
        - --bind-address=127.0.0.1
        volumeMounts:
        - name: cloudconfig
          mountPath: /etc/kubernetes
          readOnly: true
      volumes:
      - name: cloudconfig
        hostPath:
          path: /etc/kubernetes
      tolerations:
      # this is required so CCM can bootstrap itself
      - key: node.cloudprovider.kubernetes.io/uninitialized
        value: "true"
        effect: NoSchedule
      # Make sure the pod can be scheduled on master kubelet.
      - effect: NoSchedule
        operator: Exists
      # Mark the pod as a critical add-on for rescheduling.
      - key: CriticalAddonsOnly
        operator: Exists
      - effect: NoExecute
        operator: Exists
      # this is to restrict CCM to only run on master nodes
      # the node selector may vary depending on your cluster setup
      nodeSelector:
        node-role.kubernetes.io/master: ""
EOF
    }

    kubectl apply -f ${OCCM}
fi

# Assgin read daemonset/replicaset/statefulset permssion to allow node drain itself
cat <<EOF | kubectl apply --validate=false -f -
---
apiVersion: v1
items:
- apiVersion: rbac.authorization.k8s.io/v1
  kind: ClusterRole
  metadata:
    name: system:node-drainer
  rules:
  - apiGroups:
    - ""
    resources:
    - pods/eviction
    verbs:
    - create
  - apiGroups:
    - apps
    resources:
    - statefulsets
    - daemonsets
    verbs:
    - get
    - list
  - apiGroups:
    - extensions
    resources:
    - daemonsets
    verbs:
    - get
    - list
- apiVersion: rbac.authorization.k8s.io/v1
  kind: ClusterRoleBinding
  metadata:
    name: system:node-drainer
  roleRef:
    apiGroup: rbac.authorization.k8s.io
    kind: ClusterRole
    name: system:node-drainer
  subjects:
  - apiGroup: rbac.authorization.k8s.io
    kind: Group
    name: system:nodes
kind: List
metadata: {}
EOF

# Create cloud-config for csi-cinder and csi-manila
cat <<EOF | kubectl apply -f -
---
apiVersion: v1
kind: Secret
metadata:
  name: cloud-config
  namespace: kube-system
type: Opaque
stringData:
  cloud.conf: |-
    [Global]
    auth-url=$AUTH_URL
    user-id=$TRUSTEE_USER_ID
    password=$TRUSTEE_PASSWORD
    trust-id=$TRUST_ID
    region=$REGION_NAME
EOF

cat <<EOF | kubectl apply -f -
---
apiVersion: v1
kind: Secret
metadata:
  name: csi-manila-secrets
  namespace: kube-system
type: Opaque
stringData:
  os-authURL: $AUTH_URL
  os-trusteeID: $TRUSTEE_USER_ID
  os-trusteePassword: $TRUSTEE_PASSWORD
  os-trustID: $TRUST_ID
  os-region: $REGION_NAME
  os-certAuthority: /etc/kubernetes/ca-bundle.crt
EOF

# Post install file to setup some cloud provider/vendor specific configs
if [ "$POST_INSTALL_MANIFEST_URL" != "" ]; then
    kubectl apply -f "$POST_INSTALL_MANIFEST_URL"
fi

printf "Finished running ${step}\n"
