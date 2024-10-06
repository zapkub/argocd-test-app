#!/bin/bash

script_path="${0:A}"
script_dir=$(dirname "$script_path")
vendor_dir="$script_dir"/vendor

set -e
set -o xtrace


cluster_name=argocd-dev
context_name=kind-"$cluster_name"

mkdir -p "$script_dir"/vendor

__k() {
    kubectl --context="$context_name" $@
}

__istio() {
    istioctl_bin=$vendor_dir/istio-1.23.2/bin/istioctl
    if [ ! -f "$istioctl_bin" ]; then
        /bin/bash -c "cd $vendor_dir && curl -L https://istio.io/downloadIstio | ISTIO_VERSION=1.23.2 TARGET_ARCH=x86_64 sh -"
    fi
    "$istioctl_bin" --context="$context_name" $@
}

__create() {
    kind create cluster --name="$cluster_name"
}

jq_bin="$vendor_dir"/jq
__check_jq() {
    if ! echo '{}' | $jq_bin .  &> /dev/null; then
        JQ_BIN_PACKAGE_URL=https://github.com/jqlang/jq/releases/download/jq-1.7.1/jq-macos-arm64
        echo "jq is not installed in $vendor_dir"
        curl -Lo $jq_bin $JQ_BIN_PACKAGE_URL
        chmod +x $jq_bin
    fi
}

__check_jq


__create
__k get ns
__k apply -f https://raw.githubusercontent.com/metallb/metallb/v0.13.7/config/manifests/metallb-native.yaml

echo "waiting for metallb...."
waitForMetallb() {
    __k wait --namespace metallb-system --for=condition=ready pod --selector=app=metallb --timeout=90s
}
until waitForMetallb; do
    echo "Retrying for metallb...... (5s)"
    sleep 5 # Waits for 1 second before retrying
done

ipv4_address=$(docker network inspect -f '{{json .IPAM.Config}}' kind | $jq_bin -r '.[] | select(.Subnet | test("^[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+")) | .Subnet')
first_two_sections=$(echo "$ipv4_address" | cut -d'.' -f1-2)
echo "$first_two_sections"

echo "create external IP..."
__k apply -f - <<EOF
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
    name: external-ip
    namespace: metallb-system
spec:
    addresses:
    - $first_two_sections.255.200-$first_two_sections.255.250
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
    name: empty
    namespace: metallb-system
EOF
echo "cluster is ready!"

__k create ns cluster-ingress
__istio -y --context=$KUBE_CONTEXT_NAME install -f "$script_dir"/istio-operator.yaml

__k create namespace argocd
__k apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/master/manifests/install.yaml

# if [ "$(uname -m)" != "x86_64" ]; then
#     echo "Architecture is not x86_64. Exiting script."
#     exit 1
# fi

# SCRIPT_DIR="$(dirname "$(realpath "$0")")"
# K8S_DIR="$(realpath $SCRIPT_DIR/..)"

# if [ x"$GITHUB_USERNAME" == x"" ]; then
#   echo "GITHUB_USERNAME must be set"
#   exit 1
# fi

# if [ x"$GITHUB_TOKEN" == x"" ]; then
#   echo "GITHUB_TOKEN must be set"
#   exit 1
# fi

# echo "Checking kind status"
# WORKING_DIR=$HOME/.agora/id/local

# FLUX_BIN_PACKAGE_URL=https://github.com/fluxcd/flux2/releases/download/v2.0.1/flux_2.0.1_linux_amd64.tar.gz
# KIND_BIN_PACKAGE_URL=https://github.com/kubernetes-sigs/kind/releases/download/v0.22.0/kind-linux-amd64
# JQ_BIN_PACKAGE_URL=https://github.com/jqlang/jq/releases/download/jq-1.7.1/jq-linux-amd64
# NODE_IMAGE_TAG=kindest/node:v1.25.16@sha256:e8b50f8e06b44bb65a93678a65a26248fae585b3d3c2a669e5ca6c90c69dc519
# NODE_IMAGE=${NODE_IMAGE:-"docker.artifactory-ha.tri-ad.tech/$NODE_IMAGE_TAG"}

# mkdir -p $WORKING_DIR/bin
# FLUX_BIN=$WORKING_DIR/bin/flux
# KIND_BIN=$WORKING_DIR/bin/kind
# JQ_BIN=$WORKING_DIR/bin/jq

# KIND_CLUSTER_NAME=agora-speedway-local
# KUBE_CONTEXT_NAME=kind-$KIND_CLUSTER_NAME

# # make sure there is kind
# if $KIND_BIN version &> /dev/null; then
#     echo "kind is ready"
# else
#     echo "kind is not installed in $WORKING_DIR"
#     curl -Lo $KIND_BIN $KIND_BIN_PACKAGE_URL
#     chmod +x $KIND_BIN
# fi

# # make sure there is flux
# if $FLUX_BIN -v &> /dev/null; then
#     echo "flux is ready"
# else
#     echo "flux is not installed in $WORKING_DIR"
#     curl -Lo /tmp/flux.tar.gz $FLUX_BIN_PACKAGE_URL
#     tar -xzf /tmp/flux.tar.gz -C $WORKING_DIR/bin
#     chmod +x $FLUX_BIN
# fi

# if echo '{}' | $JQ_BIN .  &> /dev/null; then
#     echo "jq is ready"
# else
#     echo "jq is not installed in $WORKING_DIR"
#     curl -Lo $JQ_BIN $JQ_BIN_PACKAGE_URL
#     chmod +x $JQ_BIN
# fi

# # checking kind cluster status....
# if $KIND_BIN get clusters | grep -q $KIND_CLUSTER_NAME;then
#     echo found existed cluster, skipping create a new one....
# fi

# echo "Create new kind cluster....."
# $KIND_BIN create cluster --name $KIND_CLUSTER_NAME --image=$NODE_IMAGE
# kubectl --context=$KUBE_CONTEXT_NAME apply -f https://raw.githubusercontent.com/metallb/metallb/v0.13.7/config/manifests/metallb-native.yaml

# echo "waiting for metallb...."
# waitForMetallb() {
#     kubectl --context=$KUBE_CONTEXT_NAME wait --namespace metallb-system --for=condition=ready pod --selector=app=metallb --timeout=90s
# }
# until waitForMetallb; do
#     echo "Retrying for metallb...... (5s)"
#     sleep 5 # Waits for 1 second before retrying
# done
# ipv4_address=$(docker network inspect -f '{{json .IPAM.Config}}' kind | $JQ_BIN -r '.[] | select(.Subnet | test("^[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+")) | .Subnet')
# first_two_sections=$(echo "$ipv4_address" | cut -d'.' -f1-2)
# echo "$first_two_sections"

# echo "create external IP..."
# kubectl --context=$KUBE_CONTEXT_NAME apply -f - <<EOF
# apiVersion: metallb.io/v1beta1
# kind: IPAddressPool
# metadata:
#     name: external-ip
#     namespace: metallb-system
# spec:
#     addresses:
#     - $first_two_sections.255.200-$first_two_sections.255.250
# ---
# apiVersion: metallb.io/v1beta1
# kind: L2Advertisement
# metadata:
#     name: empty
#     namespace: metallb-system
# EOF
# echo "cluster is ready!"

# istioctl -y --context=$KUBE_CONTEXT_NAME install -f $CREATE_KIND_SCRIPT_DIR/istiooperator.yaml

# # generate TLS certificate for HTTPS setup
# openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout $CREATE_KIND_SCRIPT_DIR/tls.key -out $CREATE_KIND_SCRIPT_DIR/tls.crt -subj "/CN=agora-id.local"
# kubectl create secret tls default-tls-secret --cert=$CREATE_KIND_SCRIPT_DIR/tls.crt --key=$CREATE_KIND_SCRIPT_DIR/tls.key -n istio-system

# waitForIstio() {
#   kubectl --context=$KUBE_CONTEXT_NAME wait --namespace istio-system --for=condition=ready pod --selector=app=istio-ingressgateway --timeout=90s
# }

# echo waiting for ingress gateway
# until waitForIstio; do
#   echo "Command failed with exit code $?. Retrying..."
#   sleep 1 # Waits for 1 second before retrying
# done

# # Deploy super simple Argo CD
# kubectl create namespace argocd
# kubectl apply -n argocd -f $CREATE_KIND_SCRIPT_DIR'/argocd-base.yaml'

# # Add wcm city repository and add your GITHUB credential
# # to the cluster
# kubectl create -n argocd secret generic local-github-credential \
#     --from-literal=type=git \
#     --from-literal=url=https://github.com/wp-wcm/city \
#     --from-literal=password=$GITHUB_TOKEN \
#     --from-literal=username=$GITHUB_USERNAME
# kubectl label -n argocd secret local-github-credential "argocd.argoproj.io/secret-type=repository"

# # Prepare agora identity secret (mimic the behavior of ESO vault integration)
# kubectl create namespace agora-id-local
# kubectl label namespace agora-id-local istio-injection=enabled --overwrite

# kubectl create -n agora-id-local secret generic credential-keycloak \
#     --from-literal=KEYCLOAK_ADMIN_USERNAME=admin \
#     --from-literal=KEYCLOAK_ADMIN_PASSWORD=admin12345! \
#     --from-literal=KEYCLOAK_ADMIN_CLIENT_ID=admin-cli \
#     --from-literal=ADMIN_USERNAME=admin \
#     --from-literal=ADMIN_PASSWORD=admin12345!

# kubectl create -n agora-id-local secret generic credential-drako \
#     --from-literal=DRAKO_SESSION_COOKIE_KEY=$(openssl rand 64 | base64 -w 0)

# kubectl --context=$KUBE_CONTEXT_NAME apply -k $CREATE_KIND_SCRIPT_DIR

# echo \\n"please give a moment to wait for the cluster preparation....."
# echo "Tip:"
# echo '- To get argocd admin credential run `kubectl get secrets -n argocd argocd-initial-admin-secret -o yaml | yq '.data.password' | base64 -d`'
# echo '- Force clean the cluster run `kind delete cluster -n ' $KIND_CLUSTER_NAME
# echo '- example of hostfile setup record `172.19.255.200 id.woven-city.local argocd.woven-city.local` please run `kubectl get svc -nistio-system istio-ingressgateway -o yaml | yq .status.loadBalancer.ingress.0.ip` to check the cluster IP'