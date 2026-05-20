# Packer — hardened image baking per tenant

This directory builds **pre-hardened OS images** so that on-prem deployments
boot already-compliant rather than running compliance hardening at first-boot.
The same Ansible compliance role used by `deployments/ansible/on-prem/<tenant>/...`
is invoked at bake time so there is **one source of truth for hardening**.

> 👉 **Start here**: **[`docs/end-to-end-guide.md`](docs/end-to-end-guide.md)** is
> the single comprehensive reference — from fresh-machine setup through
> release, troubleshooting, and cleanup. Read it first.

> **arm64 + bosch uses a two-stage build** (stage 1 = OS install, stage 2 =
> ansible hardening) for fast ansible iteration. Two-stage internals are in
> **[`docs/BUILD-WORKFLOW.md`](docs/BUILD-WORKFLOW.md)**. The
> sections below describe the legacy monolith model still used for x86
> (renesas, bosch-amd64) — same concepts, single-pass.

## Why bake images?

| Approach | First-boot hardening (status quo) | Pre-baked images (this dir) |
|---|---|---|
| Time-to-ready | 8–15 min Ansible run on every node | 30–60 s — image already hardened |
| Drift surface | Each node hardens itself; one missed run = noncompliant prod node | Hardening is a build artifact; either every node has it or none do |
| FIPS enablement | Requires reboot mid-Ansible-run; brittle | Baked into the image, validated once |
| CIS audit story | "Ansible ran" — auditor needs to trust the run | Image hash is the artifact; auditor inspects one binary |
| Cost of profile change | Re-run Ansible across the fleet | Bake once, redeploy |

Pre-baking does **not** replace the runtime Ansible runs — those still install
service-specific bits (k3s, postgres, vault). It only handles the hardening
baseline (CIS-L1 / CIS-L2 / FIPS) so that piece is immutable.

## Layout

```
packer/
├── README.md
├── playbooks/
│   ├── ansible.cfg               — points Packer's ansible-provisioner at the right roles_path
│   ├── packer-bake.yml           — wrapper playbook; imports the compliance role with tenant vars
│   └── inventory.ini             — single 'default' host (Packer wires SSH dynamically)
├── templates/
│   ├── renesas-rhel9-hardened.pkr.hcl       — RHEL 9 + CIS-L2 + FIPS + Renesas branding
│   └── bosch-ubuntu2204-hardened.pkr.hcl    — Ubuntu 22.04 + CIS-L1 + Bosch branding
├── variables/
│   ├── common.pkrvars.hcl        — shared defaults (output dir, version stamp pattern)
│   ├── renesas.pkrvars.hcl       — Renesas-specific (RHEL subscription, FIPS=true, profile=cis-l2)
│   └── bosch.pkrvars.hcl         — Bosch-specific (FIPS=false, profile=cis-l1)
├── http/
│   ├── ks-rhel.cfg               — RHEL kickstart (network install seed)
│   └── user-data-ubuntu          — Ubuntu autoinstall cloud-init
├── scripts/
│   ├── build.sh                  — wrapper: `./scripts/build.sh <tenant> <provider>`
│   └── verify-image.sh           — post-build sanity (mount, check FIPS flag, check CIS-L2 fs hardening)
└── output/                       — gitignored; built artifacts land here
```

## Builders / providers

Each tenant template declares parallel `source` blocks for:

- `virtualbox-iso` — for Vagrant dev sandboxes (`.box` output)
- `qemu` — for Proxmox prod (qcow2 output)
- `vmware-iso` — for VMware Fusion engineer laptops
- `docker` — base container images for service nodes that don't need a full OS

The `build` block enumerates which sources each tenant cares about. Renesas
prod targets Proxmox (qemu) primarily; Bosch prod is mixed.

## Quick start

```bash
# Prerequisites
brew install packer ansible

# Renesas: build CIS-L2 + FIPS RHEL 9 image for Proxmox (x86_64)
./scripts/build.sh renesas qemu

# Bosch: build CIS-L1 Ubuntu 22.04 image for Vagrant (x86_64)
./scripts/build.sh bosch virtualbox

# Bosch ARM64 (for Apple Silicon dev sandboxes / future ARM server fleet)
ARCH=arm64 ./scripts/build.sh bosch qemu

# Build everything for a tenant
./scripts/build.sh renesas all
```

Output lands in `output/<tenant>/<provider>/<version>/` (x86_64) or
`output/<tenant>/arm64/<provider>/<version>/` (ARM64).

## Architecture (CPU arch, not software architecture)

A baked image is binary-incompatible across CPU architectures — an `amd64`
image cannot boot on ARM hardware and vice versa. We support both, with
the arch as an explicit dimension on every build:

| Tenant | amd64 | arm64 |
|---|---|---|
| Renesas (RHEL 9 + CIS-L2 + FIPS) | ✅ x86_64 only — RHEL FIPS 140-3 validation is x86-only | ❌ not supported (FIPS gap) |
| Bosch (Ubuntu 22.04 + CIS-L1) | ✅ Production fleet | ✅ Apple Silicon dev sandboxes + future ARM servers |

**The bake host's arch must match the guest arch** (or the host needs hardware
virtualization for the guest arch — only true for Apple Silicon Macs running
ARM guests via VirtualBox/QEMU+hvf/VMware Fusion). Cross-arch baking via
software emulation (QEMU TCG) is technically possible but takes 2–4 hours per
bake — unworkable for iteration.

In practice:
- **amd64 builds** run on x86 Linux hosts (CI runners, cloud VMs, dedicated
  bake boxes). They cannot run usefully on Apple Silicon Macs.
- **arm64 builds** run natively on Apple Silicon Macs (`accelerator = "hvf"`),
  on ARM Linux hosts (`accelerator = "kvm"`), or on ARM cloud instances
  (Graviton, Ampere).

See ADR `40-decisions/2026-05-02-multi-arch-image-baking.md` for the full
decision record.

## Vagrant box consumption (per-arch / per-provider matrix)

The bake pipeline produces **two artifact classes** alongside each other:

1. **Hypervisor-native disk** — `.qcow2` (qemu/Proxmox), `.ova` (VirtualBox),
   `.vmdk` (VMware). Used for **production deployment**.
2. **Vagrant `.box`** — produced by the `vagrant` post-processor.
   Used for **engineer dev sandboxes** via `vagrant up`.

A Vagrant box is **provider-locked**: a `virtualbox` box has `.vmdk + .ovf`
inside, a `libvirt`/`qemu` box has `.qcow2` inside. They are not interchangeable.
This means the right `--provider` flag depends on the engineer's host:

| Engineer host | Vagrant provider to use | Plugin needed | Box source |
|---|---|---|---|
| Apple Silicon Mac | `virtualbox` | bundled | **arm64 virtualbox .box** (this pipeline, `PROVIDER=virtualbox`) |
| Linux x86 (VBox) | `virtualbox` | bundled | amd64 virtualbox .box (from x86 monolith) |
| Windows / Intel Mac | `virtualbox` | bundled | amd64 virtualbox .box (from x86 monolith) |
| Linux x86 / Linux KVM | `libvirt` | `vagrant-libvirt` | (not built — qemu .box production is parked; see "qemu-on-Apple-Silicon" note below) |
| macOS (Fusion 13+) | `vmware_desktop` | `vagrant-vmware-desktop` | (not built — VMware source parked) |

### Why `virtualbox` for Apple Silicon (not `vagrant-qemu`)?

VirtualBox 7.1.6+ ships arm64 macOS support (current stable: 7.2.x — the
BETA label was removed in 7.1.2). It's the only Vagrant provider that
ships **bundled with vagrant itself** (no `vagrant plugin install` step,
no third-party plugin maintenance burden). The reference `chef/bento`
project ships virtualbox+arm64 Ubuntu 22.04 boxes with the same recipe
this pipeline uses (`vbox_guest_os_type = "Ubuntu_arm64"`, EFI firmware,
ARM64 Ubuntu installer ISO).

`vagrant-qemu` is a viable alternative — the HashiCorp `vagrant`
post-processor maps qemu source artifacts to the **libvirt** box format,
which `vagrant-qemu` shares on disk. We could re-enable that by adding
a second `vagrant` post-processor on the qemu source. Not done in v1
because it pulls in a third-party plugin and produces a second box
artifact that splits engineer mind-share. Open a ticket if you want it.

### Engineer-side workflow (Apple Silicon / arm64 / virtualbox)

```bash
# One-time setup — VirtualBox 7.1.6+ required for arm64 (current 7.2.x stable)
# Download the macOS arm64 build from https://www.virtualbox.org/wiki/Downloads
# (Homebrew's virtualbox cask also works once it's pinned to 7.1.6+.)
brew install --cask vagrant

# Add the box (path is whatever the bake produced):
vagrant box add bosch-arm64 \
  ./output/bosch/arm64/virtualbox/2026-05-04.1/bosch-ubuntu2204-cisl1-arm64-2026-05-04.1.box

# Use it
mkdir bosch-sandbox && cd bosch-sandbox
vagrant init bosch-arm64
vagrant up --provider virtualbox
vagrant ssh
```

### Engineer-side workflow (Intel / Linux / Windows / amd64 / virtualbox)

```bash
# One-time setup
# install VirtualBox 7.x stable + vagrant from your OS package manager

# Add the amd64 box (built on x86 host or CI runner — cannot be baked on Apple Silicon):
vagrant box add bosch-amd64 \
  ./output/bosch/virtualbox-iso/<version>/bosch-ubuntu2204-cisl1-<version>.box

# Use it
mkdir bosch-sandbox && cd bosch-sandbox
vagrant init bosch-amd64
vagrant up --provider virtualbox
vagrant ssh
```

## Validating templates manually

Always validate templates **one file at a time**, not by directory:

```bash
# Correct — addresses one template, supplies its var-files
packer validate \
  -var-file=variables/common.pkrvars.hcl \
  -var-file=variables/bosch.pkrvars.hcl \
  templates/bosch-ubuntu2204-hardened.pkr.hcl
```

```bash
# WRONG — `packer validate .` (or `packer validate templates/`) merges every
# .pkr.hcl file in the directory into one config and reports every shared
# variable as a "Duplicate variable definition" error. The shared variable
# names are intentional (one tenant contract, multiple OSes); they are not a
# duplication bug.
```

Use `./scripts/build.sh <tenant> <provider>` for the canonical invocation —
it always selects the right template and var-files.

## ISO sourcing

Tenant `iso_url` values point at **locally-cached ISOs** by default
(`file:///...`) for two reasons:

1. **Reliability.** `releases.ubuntu.com` and similar canonical sources
   regularly TLS-timeout under load. Local files never fail to fetch.
2. **Reproducibility.** Ubuntu/RHEL routinely rotate older point releases off
   public mirrors when newer ones ship (e.g. 22.04.4 → 22.04.5). A pinned
   local ISO + sha256 means yesterday's build hash is reproducible tomorrow.

### Where to download from (per arch)

Ubuntu hosts x86_64 ISOs at one URL family and ARM64 ISOs at another:

| Arch | Canonical | A reliable mirror |
|---|---|---|
| amd64 | `https://releases.ubuntu.com/22.04/` | `https://ftp.iij.ad.jp/pub/linux/ubuntu/releases/22.04/` |
| arm64 | `https://cdimage.ubuntu.com/releases/22.04/release/` | (cdimage is generally fast; mirrors of cdimage are spottier) |

If `releases.ubuntu.com` is unreachable from your network, IIJ is a reliable
alternative for amd64. For arm64, `cdimage.ubuntu.com` is usually fine —
cdimage mirrors exist but coverage of point releases is spottier than the
release mirror network.

To refresh a tenant's ISO:

```bash
mkdir -p ~/iso-cache
# amd64:
curl --fail -L -C - -o ~/iso-cache/ubuntu-22.04.5-live-server-amd64.iso \
  https://ftp.iij.ad.jp/pub/linux/ubuntu/releases/22.04/ubuntu-22.04.5-live-server-amd64.iso

# arm64:
curl --fail -L -C - -o ~/iso-cache/ubuntu-22.04.5-live-server-arm64.iso \
  https://cdimage.ubuntu.com/releases/22.04/release/ubuntu-22.04.5-live-server-arm64.iso

# Verify against the canonical SHA256SUMS for that arch family:
# amd64 lives at releases.ubuntu.com (or any release-mirror)
# arm64 lives at cdimage.ubuntu.com
curl -s https://cdimage.ubuntu.com/releases/22.04/release/SHA256SUMS | grep arm64
shasum -a 256 ~/iso-cache/ubuntu-22.04.5-live-server-arm64.iso
# The two hashes MUST match exactly. If they don't, delete and re-download.

# Then update the tenant's pkrvars.hcl: iso_url + iso_checksum.
```

**Always use `curl --fail`** — without it, curl writes 404 HTML pages to your
output file and returns exit 0, leaving you with a 146-byte "ISO" that
silently breaks the build.

### ARM64 build prerequisites on Apple Silicon Mac

```bash
brew install packer ansible qemu
# QEMU on Apple Silicon ships qemu-system-aarch64 + the EDK2 ARM firmware at
# /opt/homebrew/share/qemu/edk2-aarch64-code.fd (the path bosch-arm64 expects).
# If your homebrew prefix differs, override: -var qemu_efi_firmware=...

# VirtualBox on Apple Silicon: VBox 7.1.6+ supports arm64 macOS as a stable
# (non-BETA) build — download the macOS arm64 installer from virtualbox.org/wiki/Downloads.
# Standard amd64 VirtualBox cannot launch ARM guests.
# VMware Fusion 13+ supports ARM guests natively on Apple Silicon.
```

## How the compliance role is invoked

The `packer-bake.yml` playbook (under `playbooks/`) sets `roles_path` to point
at the parent repo's `ansible/playbooks/roles/`, then includes the `compliance`
role with vars supplied by the tenant `.pkrvars.hcl` file:

```yaml
- hosts: default
  become: true
  roles:
    - role: compliance
      vars:
        compliance:
          profile: "{{ lookup('env', 'COMPLIANCE_PROFILE') }}"   # cis-l1 | cis-l2
          fips_mode: "{{ lookup('env', 'FIPS_MODE') | bool }}"
          ssh_hardening: true
          audit:
            auditd_enabled: true
            rules_set: "{{ lookup('env', 'COMPLIANCE_PROFILE') }}"
```

`COMPLIANCE_PROFILE` and `FIPS_MODE` are set on Packer's `provisioner "ansible"`
block via `extra_arguments` from the tenant vars file. **No duplication** —
the role definition lives in `ansible/playbooks/roles/compliance/` and is the
same code that runs at deploy time.

## CI / verification

Post-bake, `scripts/verify-image.sh` mounts the artifact (or boots it briefly
for VM images) and asserts:

- For Renesas: `fips-mode-setup --check` returns `enabled`, `/etc/issue.net`
  contains the Renesas banner, `findmnt /tmp` shows `nosuid,nodev,noexec`.
- For Bosch: `auditd` enabled, ssh ciphers match `sshd_hardening.conf.j2`,
  `/etc/issue.net` contains the Bosch banner.

Hook into the future CI pipeline so every merge that touches `packer/` or
`ansible/playbooks/roles/compliance/` triggers a smoke build.

## See also

- ADR: `[[40-decisions/2026-05-01-packer-image-baking]]` (in the vault)
- Reference: `[[30-references/packer-structure]]` (in the vault)
- Compliance role source: `../ansible/playbooks/roles/compliance/`
- On-prem deploy entrypoints: `../deployments/ansible/on-prem/<tenant>/<env>/<service>/deploy.sh`
