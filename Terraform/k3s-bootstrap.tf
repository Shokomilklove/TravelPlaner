locals {
  k3s_bootstrap = <<-EOF
#!/bin/bash
set -euxo pipefail

export DEBIAN_FRONTEND=noninteractive

# ------------------------------------------------------------
# 0. Mount dedicated EBS volume for K3s
# ------------------------------------------------------------

echo "Waiting for dedicated EBS volume..."

DATA_DISK=""

for i in $(seq 1 60); do
  DATA_DISK=$(
    lsblk -dpno NAME,TYPE |
    awk '$2=="disk" && $1 !~ /nvme0n1$/ {print $1; exit}'
  )

  if [ -n "$DATA_DISK" ]; then
    break
  fi

  echo "Waiting for EBS volume... attempt $${i}/60"
  sleep 5
done

if [ -z "$DATA_DISK" ]; then
  echo "ERROR: Dedicated EBS volume was not found."
  lsblk
  exit 1
fi

echo "Dedicated EBS volume detected: $${DATA_DISK}"

if ! blkid "$${DATA_DISK}" >/dev/null 2>&1; then
  echo "Formatting $${DATA_DISK} as ext4..."
  mkfs.ext4 -F "$${DATA_DISK}"
fi

mkdir -p /var/lib/rancher

mount "$${DATA_DISK}" /var/lib/rancher

DATA_UUID=$(
  blkid -s UUID -o value "$${DATA_DISK}"
)

if ! grep -q "$${DATA_UUID}" /etc/fstab; then
  echo "UUID=$${DATA_UUID} /var/lib/rancher ext4 defaults,nofail 0 2" \
    >> /etc/fstab
fi

mount -a

echo "K3s data volume mounted:"
df -h /var/lib/rancher

echo "=========================================="
echo " TravelPlanner K3s bootstrap started"
echo "=========================================="

# ------------------------------------------------------------
# 1. Basic packages
# ------------------------------------------------------------

apt-get update -y

apt-get install -y \
  curl \
  ca-certificates \
  gnupg \
  git \
  unzip \
  openssl \
  postgresql-client

# ------------------------------------------------------------
# 2. AWS CLI v2
# ------------------------------------------------------------

if ! command -v aws >/dev/null 2>&1; then
  echo "Installing AWS CLI v2..."

  curl -fsSL \
    "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" \
    -o /tmp/awscliv2.zip

  unzip -q /tmp/awscliv2.zip -d /tmp

  /tmp/aws/install

  rm -rf /tmp/aws /tmp/awscliv2.zip
fi

aws --version


# ------------------------------------------------------------
# 2.1 Install WireGuard
# ------------------------------------------------------------

echo "Installing WireGuard..."

apt-get install -y \
  wireguard \
  wireguard-tools

mkdir -p /etc/wireguard
chmod 700 /etc/wireguard

echo "WireGuard package installed."

# ------------------------------------------------------------
# Configure WireGuard
# ------------------------------------------------------------
echo "Configuring WireGuard..."

mkdir -p /etc/wireguard
chmod 700 /etc/wireguard

# Generate AWS WireGuard keypair locally if it does not exist.
if [ ! -f /etc/wireguard/aws-private.key ]; then
  umask 077
  wg genkey > /etc/wireguard/aws-private.key
fi

AWS_WG_PRIVATE_KEY=$(cat /etc/wireguard/aws-private.key)

AWS_WG_PUBLIC_KEY=$(printf '%s' "$${AWS_WG_PRIVATE_KEY}" | wg pubkey)

chmod 600 /etc/wireguard/aws-private.key

# Publish ONLY the AWS public key to SSM.
aws ssm put-parameter \
  --region eu-central-1 \
  --name "/travel-planner/wireguard/aws-public-key" \
  --type "String" \
  --value "$${AWS_WG_PUBLIC_KEY}" \
  --overwrite

echo "AWS WireGuard public key published to SSM."

# Wait for Windows public key.
until WINDOWS_WG_PUBLIC_KEY=$(
  aws ssm get-parameter \
    --region eu-central-1 \
    --name "/travel-planner/wireguard/windows-public-key" \
    --query "Parameter.Value" \
    --output text 2>/dev/null
) && [ -n "$${WINDOWS_WG_PUBLIC_KEY}" ] && \
   [ "$${WINDOWS_WG_PUBLIC_KEY}" != "None" ]; do

  echo "Waiting for Windows WireGuard public key..."
  sleep 10
done

cat > /etc/wireguard/wg0.conf <<WGEOF
[Interface]
Address = 10.50.0.2/24
ListenPort = 51820
PrivateKey = $${AWS_WG_PRIVATE_KEY}

[Peer]
PublicKey = $${WINDOWS_WG_PUBLIC_KEY}
AllowedIPs = 10.50.0.1/32
PersistentKeepalive = 25
WGEOF

chmod 600 /etc/wireguard/wg0.conf

systemctl enable wg-quick@wg0
systemctl restart wg-quick@wg0

echo "WireGuard configured successfully."
wg show


# ------------------------------------------------------------
# 3. Install K3s
# ------------------------------------------------------------

if ! systemctl is-active --quiet k3s; then
  echo "Installing K3s..."

  curl -sfL https://get.k3s.io | sh -
fi

systemctl enable k3s
systemctl start k3s

# ------------------------------------------------------------
# 4. Wait for Kubernetes
# ------------------------------------------------------------

echo "Waiting for K3s..."

until /usr/local/bin/k3s kubectl get nodes >/dev/null 2>&1; do
  sleep 5
done

/usr/local/bin/k3s kubectl get nodes

echo "Waiting for Flannel network..."

until [ -s /run/flannel/subnet.env ]; do
  echo "Waiting for /run/flannel/subnet.env..."
  sleep 5
done

echo "Flannel network is ready:"
cat /run/flannel/subnet.env

echo "Waiting for Kubernetes node to become Ready..."

until /usr/local/bin/k3s kubectl get nodes \
  -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].status}' \
  2>/dev/null | grep -q True; do

  echo "Node is not Ready yet..."
  sleep 5
done

echo "Kubernetes node is Ready."

# ------------------------------------------------------------
# 5. kubectl configuration
# ------------------------------------------------------------

mkdir -p /home/ubuntu/.kube

cp /etc/rancher/k3s/k3s.yaml \
  /home/ubuntu/.kube/config

chown -R ubuntu:ubuntu /home/ubuntu/.kube
chmod 600 /home/ubuntu/.kube/config

export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

ln -sf /usr/local/bin/k3s /usr/local/bin/kubectl

echo "Kubernetes API is ready."

# ------------------------------------------------------------
# 5.1 Create application namespace FIRST
# ------------------------------------------------------------

echo "Creating travel-planner namespace..."

kubectl create namespace travel-planner \
  --dry-run=client \
  -o yaml \
  | kubectl apply -f -

echo "travel-planner namespace is ready."

# ------------------------------------------------------------
# 5.2 Configure CoreDNS for AWS private DNS
# ------------------------------------------------------------

echo "Configuring CoreDNS for travel-planner.internal..."

kubectl apply -f - <<'COREDNS_EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: coredns-custom
  namespace: kube-system
data:
  travel-planner.server: |
    travel-planner.internal:53 {
        errors
        cache 30
        forward . 10.0.0.2
    }
COREDNS_EOF

echo "Restarting CoreDNS..."

kubectl -n kube-system rollout restart deployment coredns

kubectl -n kube-system rollout status deployment coredns \
  --timeout=120s

echo "CoreDNS private DNS configuration applied."

# ------------------------------------------------------------
# 5.3 Verify PostgreSQL private DNS
# ------------------------------------------------------------

echo "Testing PostgreSQL DNS resolution..."

until kubectl run dns-test \
  -n travel-planner \
  --image=busybox:1.36 \
  --restart=Never \
  --rm \
  --attach \
  --quiet \
  -- nslookup postgres.travel-planner.internal \
  >/tmp/dns-test-result 2>&1; do

  echo "PostgreSQL DNS is not ready yet..."
  cat /tmp/dns-test-result || true

  sleep 5
done

cat /tmp/dns-test-result

echo "PostgreSQL DNS resolution works."

# ------------------------------------------------------------
# 6. Install Helm
# ------------------------------------------------------------

if ! command -v helm >/dev/null 2>&1; then
  echo "Installing Helm..."

  curl -fsSL \
    https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 \
    | bash
fi

helm version

# ------------------------------------------------------------
# 7. Wait for PostgreSQL password in SSM
# ------------------------------------------------------------

echo "Waiting for PostgreSQL password..."

until DB_PASSWORD=$(
  aws ssm get-parameter \
    --region ${var.aws_region} \
    --name "/travel-planner/postgres-password" \
    --with-decryption \
    --query "Parameter.Value" \
    --output text 2>/dev/null
) && [ -n "$${DB_PASSWORD}" ]; do

  echo "PostgreSQL password not available yet..."
  sleep 10
done

echo "PostgreSQL password received from SSM."

# ------------------------------------------------------------
# 7.1 Wait for shared INTERNAL_API_TOKEN
# ------------------------------------------------------------

echo "Waiting for shared INTERNAL_API_TOKEN..."

until INTERNAL_API_TOKEN=$(
  aws ssm get-parameter \
    --region ${var.aws_region} \
    --name "/travel-planner/internal-api-token" \
    --with-decryption \
    --query "Parameter.Value" \
    --output text 2>/dev/null
) && [ -n "$${INTERNAL_API_TOKEN}" ]; do

  echo "INTERNAL_API_TOKEN not available yet..."
  sleep 10
done

echo "Shared INTERNAL_API_TOKEN received."
# ------------------------------------------------------------
# 8. Create application Kubernetes Secret
# ------------------------------------------------------------

echo "Creating Kubernetes Secret..."

kubectl create secret generic trip-service-secrets \
  --namespace travel-planner \
  --from-literal=POSTGRES_USER=travel \
  --from-literal=POSTGRES_PASSWORD="$${DB_PASSWORD}" \
  --from-literal=POSTGRES_DB=travel \
  --from-literal=SECRET_KEY="$$(openssl rand -hex 32)" \
  --from-literal=JWT_SECRET_KEY="$$(openssl rand -hex 32)" \
  --from-literal=INTERNAL_API_TOKEN="$${INTERNAL_API_TOKEN}" \
  --dry-run=client \
  -o yaml \
  | kubectl apply -f -

echo "Kubernetes application secret created."

# ------------------------------------------------------------
# 9. Install Helm repositories
# ------------------------------------------------------------

echo "Adding Helm repositories..."

helm repo add argo \
  https://argoproj.github.io/argo-helm \
  || true

helm repo add prometheus-community \
  https://prometheus-community.github.io/helm-charts \
  || true

helm repo add grafana \
  https://grafana.github.io/helm-charts \
  || true

helm repo add grafana-community \
  https://grafana-community.github.io/helm-charts \
  || true

helm repo update

# ------------------------------------------------------------
# 10. Install Argo CD
# ------------------------------------------------------------

echo "Installing Argo CD..."

kubectl create namespace argocd \
  --dry-run=client \
  -o yaml \
  | kubectl apply -f -

helm upgrade --install argocd argo/argo-cd \
  --namespace argocd \
  --set server.service.type=ClusterIP \
  --wait \
  --timeout 10m

echo "Argo CD installed."

# ------------------------------------------------------------
# 10.1 Wait for Argo CD controllers
# ------------------------------------------------------------

echo "Waiting for Argo CD to become ready..."

kubectl rollout status deployment/argocd-server \
  -n argocd \
  --timeout=300s

kubectl rollout status deployment/argocd-repo-server \
  -n argocd \
  --timeout=300s

kubectl rollout status deployment/argocd-applicationset-controller \
  -n argocd \
  --timeout=300s

echo "Argo CD is ready."

# ------------------------------------------------------------
# 11. Install Prometheus + Grafana + Alertmanager
# ------------------------------------------------------------

echo "Installing monitoring stack..."

kubectl create namespace monitoring \
  --dry-run=client \
  -o yaml \
  | kubectl apply -f -

MONITORING_INSTALLED=false

for attempt in 1 2 3 4 5
do
  echo "=========================================="
  echo " Monitoring installation attempt $${attempt}/5"
  echo "=========================================="

  if helm upgrade --install monitoring \
    prometheus-community/kube-prometheus-stack \
    --namespace monitoring \
    --set grafana.enabled=true \
    --set prometheus.enabled=true \
    --set alertmanager.enabled=true \
    --set grafana.service.type=ClusterIP \
    --wait \
    --timeout 15m
  then

    MONITORING_INSTALLED=true

    echo "Monitoring stack installed successfully."

    break
  fi

  echo "Monitoring installation failed."
  echo "Waiting 30 seconds before retry..."

  sleep 30

  echo "Checking Kubernetes API..."

  kubectl get nodes || true
  kubectl get pods -A || true

done

if [ "$${MONITORING_INSTALLED}" != "true" ]; then
  echo "ERROR: Monitoring stack failed after 5 attempts."

  echo "--- Kubernetes nodes ---"
  kubectl get nodes -o wide || true

  echo "--- Monitoring namespace ---"
  kubectl get all -n monitoring || true

  echo "--- CRDs ---"
  kubectl get crd | grep -E \
    'prometheus|servicemonitor|alertmanager|scrape' || true

  exit 1
fi

echo "Prometheus/Grafana/Alertmanager installed."

# ------------------------------------------------------------
# 11.1 Verify monitoring
# ------------------------------------------------------------

echo "Waiting for monitoring pods..."

kubectl get pods -n monitoring

# ------------------------------------------------------------
# 12. Install Loki
# ------------------------------------------------------------

echo "Installing Loki..."

kubectl create namespace loki \
  --dry-run=client \
  -o yaml \
  | kubectl apply -f -

helm upgrade --install loki grafana-community/loki \
  --namespace loki \
  --set deploymentMode=Monolithic \
  --set singleBinary.replicas=1 \
  --set backend.replicas=0 \
  --set read.replicas=0 \
  --set write.replicas=0 \
  --set ingester.replicas=0 \
  --set querier.replicas=0 \
  --set queryFrontend.replicas=0 \
  --set queryScheduler.replicas=0 \
  --set distributor.replicas=0 \
  --set compactor.replicas=0 \
  --set indexGateway.replicas=0 \
  --set bloomPlanner.replicas=0 \
  --set bloomBuilder.replicas=0 \
  --set bloomGateway.replicas=0 \
  --set loki.auth_enabled=false \
  --set loki.commonConfig.replication_factor=1 \
  --set loki.storage.type=filesystem \
  --set loki.schemaConfig.configs[0].from=2024-04-01 \
  --set loki.schemaConfig.configs[0].store=tsdb \
  --set loki.schemaConfig.configs[0].object_store=filesystem \
  --set loki.schemaConfig.configs[0].schema=v13 \
  --set loki.schemaConfig.configs[0].index.prefix=loki_index_ \
  --set loki.schemaConfig.configs[0].index.period=24h \
  --set loki.common.storage.filesystem.chunks_directory=/var/loki/chunks \
  --set loki.common.storage.filesystem.rules_directory=/var/loki/rules \
  --set loki.limits_config.allow_structured_metadata=true \
  --set loki.limits_config.volume_enabled=true \
  --set singleBinary.persistence.enabled=true \
  --set singleBinary.persistence.storageClass=local-path \
  --set singleBinary.persistence.accessModes[0]=ReadWriteOnce \
  --set singleBinary.persistence.size=10Gi \
  --set minio.enabled=false \
  --set chunksCache.enabled=false \
  --set resultsCache.enabled=false \
  --wait \
  --timeout 15m

echo "Loki installed."

# ------------------------------------------------------------
# 13. Install Grafana Alloy
# ------------------------------------------------------------

echo "Installing Grafana Alloy..."

kubectl create namespace alloy \
  --dry-run=client \
  -o yaml \
  | kubectl apply -f -

helm upgrade --install alloy \
  grafana/alloy \
  --namespace alloy \
  --set controller.type=daemonset \
  --wait \
  --timeout 10m

echo "Grafana Alloy installed."

# ------------------------------------------------------------
# 14. Wait for Argo CD Application CRD
# ------------------------------------------------------------

echo "Waiting for Argo CD Application CRD..."

until kubectl get crd applications.argoproj.io >/dev/null 2>&1; do
  echo "Argo CD Application CRD not ready yet..."
  sleep 5
done

echo "Argo CD Application CRD is ready."

# ------------------------------------------------------------
# 15. Create Argo CD Application
# ------------------------------------------------------------

echo "Creating Argo CD Application..."

cat <<'ARGOEOF' > /tmp/travel-planner-argocd.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: travel-planner
  namespace: argocd
spec:
  project: default

  source:
    repoURL: https://github.com/Shokomilklove/TravelPlaner.git
    targetRevision: aws-deployment
    path: deploy/helm/travel-planner

    helm:
      valueFiles:
        - values-aws.yaml

  destination:
    server: https://kubernetes.default.svc
    namespace: travel-planner

  syncPolicy:
    automated:
      prune: true
      selfHeal: true

    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true
ARGOEOF

kubectl apply \
  -f /tmp/travel-planner-argocd.yaml

rm -f /tmp/travel-planner-argocd.yaml

echo "Argo CD Application created."

# ------------------------------------------------------------
# 16. Verify installation
# ------------------------------------------------------------

echo "=========================================="
echo " K3s bootstrap verification"
echo "=========================================="

echo "--- Nodes ---"
kubectl get nodes -o wide

echo "--- Namespaces ---"
kubectl get namespaces

echo "--- CoreDNS ---"
kubectl get configmap coredns-custom -n kube-system
kubectl get pods -n kube-system -l k8s-app=kube-dns

echo "--- Argo CD ---"
kubectl get pods -n argocd

echo "--- Monitoring ---"
kubectl get pods -n monitoring

echo "--- Loki ---"
kubectl get pods -n loki

echo "--- Alloy ---"
kubectl get pods -n alloy

echo "--- TravelPlanner ---"
kubectl get pods -n travel-planner

echo "--- Argo Application ---"
kubectl get application travel-planner \
  -n argocd \
  -o wide || true

echo "=========================================="
echo " TravelPlanner K3s bootstrap completed"
echo "=========================================="
EOF
}