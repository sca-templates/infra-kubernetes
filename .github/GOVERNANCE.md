# Governance

How this project makes decisions, who holds key roles, and how the project
survives the loss of any single person.

## Decision model

**Benevolent dictator (single-maintainer).** Santiago1010 is the final
decision-maker for all changes to this repository. No change lands without
his approval, and he may overrule any discussion or proposal.

This is intentional: the project is small, single-authored, and the
decision cost of a committee would exceed the benefit. If the project grows
beyond 3 active contributors, a lightweight meritocracy model is adopted
(votes weighted by recent contribution count; Santiago1010 retains a tiebreak).

## Key roles

| Role | Responsibilities | Current holder |
| --- | --- | --- |
| **Project lead / maintainer** | Final merge authority; sets roadmap priorities; triages issues and PRs; defines security response; signs releases | Santiago1010 |
| **Contributor** | Opens PRs, reports bugs, proposes features; must follow CONTRIBUTING.md and the DCO process | Anyone |
| **Security responder** | Triage of private vulnerability reports; coordinates fix and disclosure | Santiago1010 (same as maintainer) |
| **Bus-factor backup** | Has repository admin access; can create/close issues, merge PRs, tag releases if the lead is unavailable | **[to be assigned — see Access continuity]** |

## Dispute resolution

1. Discuss on the relevant issue or PR.
2. If unresolved after reasonable time (7 days), the project lead makes a
   final call.
3. The decision is recorded in the issue/PR and (if architectural) in
   `docs/architecture.md` under the Deviations log.

There is no formal appeals process. The project lead's word is final.

## Access continuity

This project MUST be able to continue with minimal interruption if the
current maintainer dies, is incapacitated, or is otherwise unable to
continue. The following are in place:

- **Repository admin access**: at least one other GitHub account (the
  "bus-factor backup") has admin access to the `sca-templates` organization
  repository. This person can merge, tag, and manage releases.
- **GPG/SSH signing keys**: the maintainer's key is backed up in a
  physical lockbox accessible to a designated person. The backup
  signer has the authority and means to sign future tags/releases.
- **Documentation**: this file, `SECURITY.md`, and `CONTRIBUTING.md` are
  sufficient for a new maintainer to pick up the project without prior
  context.
- **Bus factor**: currently **1**. The goal is **≥2** once a second
  maintainer is onboarded (see `CODEOWNERS`). The second maintainer
  must be an independent contributor (not the same person under another
  account) to satisfy the OpenSSF Best Practices silver badge.

## Changes to this document

Changes to governance require the same approval as any other change: a PR
merged by the project lead. Governance changes are not retroactive.
