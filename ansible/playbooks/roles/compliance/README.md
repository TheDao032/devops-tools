# compliance role

Applies a CIS-Benchmark / FIPS hardening profile selected by the `compliance.profile`
variable. Profiles compose: `cis-l2` extends `cis-l1`; `fips` is an additional toggle
that can stack on top of either CIS profile.

## Layout

```
compliance/
├── defaults/main.yml          # default knobs (audit, ssh, password policy, banner)
├── handlers/main.yml          # service restarts
├── meta/main.yml              # role metadata
├── tasks/
│   ├── main.yml               # dispatcher — reads compliance.profile, includes the right files
│   └── common.yml             # baseline applied for every profile
├── cis-l1/tasks/main.yml      # CIS Benchmark Level 1 (server)
├── cis-l2/tasks/main.yml      # CIS Benchmark Level 2 — adds to cis-l1
├── fips/tasks/main.yml        # FIPS 140-3 kernel + crypto policy toggles
└── templates/
    ├── auditd-cis.rules.j2
    ├── sshd_hardening.conf.j2
    └── issue.net.j2
```

## Inputs (under `compliance:` in group_vars)

| key | type | example | meaning |
|---|---|---|---|
| `profile` | string | `cis-l1` | one of `cis-l1`, `cis-l2`, `none` |
| `fips_mode` | bool | `false` | enable FIPS 140-3 mode (independent of CIS) |
| `audit.auditd_enabled` | bool | `true` | install + start auditd, deploy rules |
| `audit.forward_to` | string | `10.42.0.20:514` | remote syslog target for `auditd` |
| `audit.rules_set` | string | `cis-l2` | which rule template to render |
| `ssh_hardening` | bool | `true` | render `sshd_hardening.conf` |
| `password_policy.*` | dict | see defaults | pwquality + faillock |
| `banner` | string | `RENESAS — Authorized…` | issue.net banner |

The role exits cleanly when `profile == none` and `fips_mode == false` (no-op).

## Idempotency & safety

Tasks use `tags: [compliance, cis, fips]` so an operator can run a single profile
in isolation. Every task that mutates state notifies a handler — there are no
in-line restarts.

## How to call

```yaml
# in any playbook
- hosts: all
  roles:
    - role: compliance
      tags: [compliance]
```

The role reads `compliance.*` from layered group_vars (set in `_company` for the
tenant baseline; can be overridden at leaf level for per-cluster exceptions).
