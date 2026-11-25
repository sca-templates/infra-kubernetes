#!/usr/bin/env bash
# Copyright (c) 2026 sca-templates contributors
# SPDX-License-Identifier: MIT
# versions.sh — single source of truth for the pinned platform CLI toolchain.
# Sourced by bootstrap/sca.sh; made available to `make` through .env overrides.
# Never float `latest` (docs/security.md). Keep in sync with docs/ci-cd.md.
KUBECTL_VERSION="${KUBECTL_VERSION:-v1.36.4}"
HELM_VERSION="${HELM_VERSION:-v4.2.4}"

# Cloud emulator (dev/CI only — not a platform component; see docs/ci-cd.md).
# Provider-agnostic seam: `aws` is Floci. Pinned by version, never `latest`.
FLOCI_IMAGE="${FLOCI_IMAGE:-floci/floci:2.3.0}"
AWS_CLI_IMAGE="${AWS_CLI_IMAGE:-amazon/aws-cli:2.38.1}"

# EKS substrate of the cloud emulator (dev/CI only; the platform's only cluster
# substrate). Floci backs EKS with a real single-node k3s container and an OCI
# ECR registry;
# these are emulator coordinates (account/subnet/role are Floci's own placeholders),
# never real AWS. The image pushed to ECR is the already-pinned AWS_CLI_IMAGE
# (this repo builds nothing). See docs/ci-cd.md.
FLOCI_EKS_CLUSTER="${FLOCI_EKS_CLUSTER:-sca-eks}"
FLOCI_EKS_CONTEXT="${FLOCI_EKS_CONTEXT:-floci-eks}"
FLOCI_EKS_NETWORK="${FLOCI_EKS_NETWORK:-sca-eks}"
FLOCI_EKS_K3S_VERSION="${FLOCI_EKS_K3S_VERSION:-v1.34.1-k3s1}"
FLOCI_EKS_K3S_IMAGE="${FLOCI_EKS_K3S_IMAGE:-rancher/k3s:${FLOCI_EKS_K3S_VERSION}}"
FLOCI_SERVICES_EKS_DISABLE_CNI="${FLOCI_SERVICES_EKS_DISABLE_CNI:-true}"
FLOCI_EKS_IAM_USER="${FLOCI_EKS_IAM_USER:-eks-admin}"
FLOCI_EKS_ROLE_ARN="${FLOCI_EKS_ROLE_ARN:-arn:aws:iam::000000000000:role/eks-role}"
FLOCI_EKS_SUBNET="${FLOCI_EKS_SUBNET:-subnet-default-us-east-1-a}"
FLOCI_EKS_ECR_REPO="${FLOCI_EKS_ECR_REPO:-sca-smoke}"
FLOCI_AWS_REGION="${FLOCI_AWS_REGION:-us-east-1}"
FLOCI_AWS_ACCOUNT="${FLOCI_AWS_ACCOUNT:-000000000000}"

# Bootstrap-managed CNI substrate (dev/CI tooling only; not a catalog component).
# Calico iptables + VXLAN + WireGuard is the D2-validated dataplane; Floci's
# disabled CNI also disables its bundled kube-proxy, so a pinned kube-proxy
# DaemonSet is part of the substrate. See docs/ci-cd.md.
CALICO_VERSION="${CALICO_VERSION:-v3.31.7}"
CALICO_MANIFEST_URL="${CALICO_MANIFEST_URL:-https://raw.githubusercontent.com/projectcalico/calico/${CALICO_VERSION}/manifests/calico-vxlan.yaml}"
CALICO_MANIFEST_SHA256="${CALICO_MANIFEST_SHA256:-324475bc90d0fc6b432092b91a011190fdaed47823fcc936762ea58507c6a5a3}"
KUBE_PROXY_VERSION="${KUBE_PROXY_VERSION:-v1.34.1}"
KUBE_PROXY_IMAGE="${KUBE_PROXY_IMAGE:-registry.k8s.io/kube-proxy:${KUBE_PROXY_VERSION}}"
CNI_SMOKE_SERVER_IMAGE="${CNI_SMOKE_SERVER_IMAGE:-nginxinc/nginx-unprivileged:1.27-alpine}"
CNI_SMOKE_CLIENT_IMAGE="${CNI_SMOKE_CLIENT_IMAGE:-curlimages/curl:8.10.1}"
