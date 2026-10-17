#!/usr/bin/env bash
# Copyright (c) 2026 sca-templates contributors
# SPDX-License-Identifier: MIT
# versions.sh — single source of truth for the pinned platform CLI toolchain.
# Sourced by bootstrap/sca.sh; made available to `make` through .env overrides.
# Never float `latest` (docs/security.md). Keep in sync with docs/ci-cd.md.
KUBECTL_VERSION="${KUBECTL_VERSION:-v1.36.4}"
HELM_VERSION="${HELM_VERSION:-v4.2.4}"
KIND_VERSION="${KIND_VERSION:-v0.32.0}"

# Cloud emulator (dev/CI only — not a platform component; see docs/ci-cd.md).
# Provider-agnostic seam: `aws` is Floci. Pinned by version, never `latest`.
FLOCI_IMAGE="${FLOCI_IMAGE:-floci/floci:2.3.0}"
AWS_CLI_IMAGE="${AWS_CLI_IMAGE:-amazon/aws-cli:2.38.1}"

# EKS substrate of the cloud emulator (dev/CI only; `SMOKE_SUBSTRATE=eks`).
# Floci backs EKS with a real single-node k3s container and an OCI ECR registry;
# these are emulator coordinates (account/subnet/role are Floci's own placeholders),
# never real AWS. The image pushed to ECR is the already-pinned AWS_CLI_IMAGE
# (this repo builds nothing). See docs/ci-cd.md.
FLOCI_EKS_CLUSTER="${FLOCI_EKS_CLUSTER:-sca-eks}"
FLOCI_EKS_CONTEXT="${FLOCI_EKS_CONTEXT:-floci-eks}"
FLOCI_EKS_NETWORK="${FLOCI_EKS_NETWORK:-sca-eks}"
FLOCI_EKS_IAM_USER="${FLOCI_EKS_IAM_USER:-eks-admin}"
FLOCI_EKS_ROLE_ARN="${FLOCI_EKS_ROLE_ARN:-arn:aws:iam::000000000000:role/eks-role}"
FLOCI_EKS_SUBNET="${FLOCI_EKS_SUBNET:-subnet-default-us-east-1-a}"
FLOCI_EKS_ECR_REPO="${FLOCI_EKS_ECR_REPO:-sca-smoke}"
FLOCI_AWS_REGION="${FLOCI_AWS_REGION:-us-east-1}"
FLOCI_AWS_ACCOUNT="${FLOCI_AWS_ACCOUNT:-000000000000}"
