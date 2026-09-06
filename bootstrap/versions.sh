#!/usr/bin/env bash
# Copyright (c) 2026 sca-templates contributors
# SPDX-License-Identifier: MIT
# versions.sh — single source of truth for the pinned platform CLI toolchain.
# Sourced by bootstrap/sca.sh; made available to `make` through .env overrides.
# Never float `latest` (docs/security.md). Keep in sync with docs/ci-cd.md.
KUBECTL_VERSION="${KUBECTL_VERSION:-v1.36.4}"
HELM_VERSION="${HELM_VERSION:-v4.2.4}"
KIND_VERSION="${KIND_VERSION:-v0.32.0}"