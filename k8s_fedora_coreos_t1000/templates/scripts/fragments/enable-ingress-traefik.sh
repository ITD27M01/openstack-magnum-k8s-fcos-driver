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

INGRESS_TRAEFIK_MANIFEST=/srv/magnum/kubernetes/ingress-traefik.yaml
INGRESS_TRAEFIK_MANIFEST_CONTENT=$(cat <<EOF
---
kind: ConfigMap
apiVersion: v1
metadata:
  name: ingress-traefik
  namespace: kube-system
  labels:
    k8s-app: ingress-traefik-backend
data:
  traefik.toml: |-
    logLevel = "INFO"
    defaultEntryPoints = ["http", "https"]
    [metrics]
      [metrics.prometheus]
        entryPoint = "metrics"
    [api]
    [kubernetes]
    [entryPoints]
      [entryPoints.http]
        address = ":80"
      [entryPoints.https]
        address = ":443"
      [entryPoints.metrics]
        address = ":8082"
        [entryPoints.https.tls]
          cipherSuites = [
            "TLS_ECDHE_ECDSA_WITH_CHACHA20_POLY1305",
            "TLS_ECDHE_RSA_WITH_CHACHA20_POLY1305",
            "TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384",
            "TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384",
            "TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256",
            "TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256",
            "TLS_ECDHE_RSA_WITH_AES_128_CBC_SHA256",
            "TLS_ECDHE_ECDSA_WITH_AES_128_CBC_SHA256",
            "TLS_ECDHE_RSA_WITH_AES_256_CBC_SHA",
            "TLS_ECDHE_RSA_WITH_AES_128_CBC_SHA",
            "TLS_ECDHE_ECDSA_WITH_AES_256_CBC_SHA",
            "TLS_ECDHE_ECDSA_WITH_AES_128_CBC_SHA",
            "TLS_RSA_WITH_AES_256_GCM_SHA384",
            "TLS_RSA_WITH_AES_128_GCM_SHA256",
            "TLS_RSA_WITH_AES_128_CBC_SHA256",
            "TLS_RSA_WITH_AES_256_CBC_SHA",
            "TLS_RSA_WITH_AES_128_CBC_SHA"
          ]
---
kind: DaemonSet
apiVersion: apps/v1
metadata:
  name: ingress-traefik
  namespace: kube-system
  labels:
    k8s-app: ingress-traefik-backend
spec:
  selector:
    matchLabels:
      k8s-app: ingress-traefik-backend
      name: ingress-traefik-backend
  template:
    metadata:
      labels:
        k8s-app: ingress-traefik-backend
        name: ingress-traefik-backend
    spec:
      serviceAccountName: ingress-traefik
      terminationGracePeriodSeconds: 60
      hostNetwork: true
      containers:
      - image: $(_set_prefix 'docker.io/')traefik:${TRAEFIK_INGRESS_CONTROLLER_TAG}
        name: ingress-traefik-backend
        ports:
        - name: http
          containerPort: 80
          hostPort: 80
        - name: https
          containerPort: 443
          hostPort: 443
        - name: admin
          containerPort: 8080
        - name: metrics
          containerPort: 8082
        securityContext:
          capabilities:
            drop:
            - ALL
            add:
            - NET_BIND_SERVICE
        volumeMounts:
        - name: ingress-traefik
          mountPath: /etc/traefik/traefik.toml
          subPath: traefik.toml
      volumes:
      - name: ingress-traefik
        configMap:
          name: ingress-traefik
      nodeSelector:
        role: ${INGRESS_CONTROLLER_ROLE}
---
kind: Service
apiVersion: v1
metadata:
  name: ingress-traefik
  namespace: kube-system
  labels:
    k8s-app: traefik
spec:
  selector:
    k8s-app: ingress-traefik-backend
  ports:
    - name: http
      protocol: TCP
      port: 80
    - name: https
      protocol: TCP
      port: 443
    - name: admin
      protocol: TCP
      port: 8080
    - name: metrics
      port: 9100
      protocol: TCP
      targetPort: metrics
---
kind: ClusterRole
apiVersion: rbac.authorization.k8s.io/v1beta1
metadata:
  name: ingress-traefik
rules:
  - apiGroups:
      - ""
    resources:
      - services
      - endpoints
      - secrets
    verbs:
      - get
      - list
      - watch
  - apiGroups:
      - extensions
    resources:
      - ingresses
    verbs:
      - get
      - list
      - watch
---
kind: ClusterRoleBinding
apiVersion: rbac.authorization.k8s.io/v1beta1
metadata:
  name: ingress-traefik
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: ingress-traefik
subjects:
- kind: ServiceAccount
  name: ingress-traefik
  namespace: kube-system
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: ingress-traefik
  namespace: kube-system
EOF
)

writeFile $INGRESS_TRAEFIK_MANIFEST "$INGRESS_TRAEFIK_MANIFEST_CONTENT"

INGRESS_TRAEFIK_BIN="/srv/magnum/kubernetes/bin/ingress-traefik"
INGRESS_TRAEFIK_SERVICE="/etc/systemd/system/ingress-traefik.service"

# Binary for ingress traefik
INGRESS_TRAEFIK_BIN_CONTENT='''#!/bin/sh
until  [ "ok" = "$(curl --silent http://127.0.0.1:8080/healthz)" ]
do
    echo "Waiting for Kubernetes API..."
    sleep 5
done

# Check if all resources exist already before creating them
kubectl -n kube-system get service ingress-traefik
if [ "$?" != "0" ] && \
        [ -f "'''${INGRESS_TRAEFIK_MANIFEST}'''" ]; then
    kubectl create -f '''${INGRESS_TRAEFIK_MANIFEST}'''
fi
'''
writeFile $INGRESS_TRAEFIK_BIN "$INGRESS_TRAEFIK_BIN_CONTENT"


# Service for ingress traefik
INGRESS_TRAEFIK_SERVICE_CONTENT='''[Unit]
Requires=kube-apiserver.service

[Service]
User=root
Group=root
Type=simple
Restart=on-failure
EnvironmentFile=-/etc/kubernetes/config
ExecStart=/bin/bash '''${INGRESS_TRAEFIK_BIN}'''
RestartSec=10

[Install]
WantedBy=multi-user.target
'''
writeFile $INGRESS_TRAEFIK_SERVICE "$INGRESS_TRAEFIK_SERVICE_CONTENT"

chown root:root ${INGRESS_TRAEFIK_BIN}
chmod 0755 ${INGRESS_TRAEFIK_BIN}

chown root:root ${INGRESS_TRAEFIK_SERVICE}
chmod 0644 ${INGRESS_TRAEFIK_SERVICE}

# Launch the ingress traefik service
set -x
ssh_cmd="ssh -F /srv/magnum/.ssh/config root@localhost"
$ssh_cmd systemctl daemon-reload
$ssh_cmd systemctl enable ingress-traefik.service
$ssh_cmd systemctl start --no-block ingress-traefik.service
