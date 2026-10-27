# Phase A Migration Inventory

## 1. Keycloak References (403 total found)
Keycloak components to remove and replace with Zitadel:
- **ArgoCD apps**: keycloak-*.yaml (4 envs)
- **Infrastructure**: infrastructure/keycloak/
- **Env configs**: envs/*/keycloak.yaml
- **Database**: keycloak-db cluster in postgres-app (may be removable)
- **Secrets**: secret/keycloak/* (admin, test-user), secret/keycloak-db/*
- **Namespace**: keycloak
- **Kong routes**: Routes to keycloak.local
- **Service template**: May have OIDC integration
- **Docs**: Extensive documentation to update

**Action**: Complete inventory of OIDC clients, must migrate to Zitadel or remove.

## 2. Linkerd References (3 found)
- docs/ci-cd.md: mentions linkerd.io/inject
- charts/service-template/templates/deployment.yaml:18 has linkerd.io/inject: enabled
- bootstrap/smoke-linkerd.sh: annotates namespace

**Action**: Remove annotations, remove linkerd-crds and linkerd-control-plane, migrate to CNI mTLS.

## 3. Kafka/Strimzi References (203 total found)
- **Strimzi operator**: infrastructure/strimzi/, in all apps-*.yaml
- **Kafka CRs**: infrastructure/kafka/, argocd/kafka-*.yaml
- **Env configs**: envs/*/strimzi.yaml
- **Secrets**: secret/kafka/*
- **Namespace**: strimzi, data contains Kafka CRs
- **Smoke tests**: bootstrap/smoke-kafka.sh

**Action**: Replace with NATS JetStream (togglable), remove all Kafka/Strimzi.

## 4. CNPG/Postgres References
- postgres-app with app and keycloak-db clusters
- Need to ensure backups/PITR for RDS replacement

## 5. Velero (not yet deployed)
- Phase 18 planned, needs to be prioritized

## Next Steps
1. Create GitHub issues for all epics and sub-issues
2. Link to milestones and Kubernetes Planning project
3. Start implementing Phase B (Velero/Backups) after issues created
