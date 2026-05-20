# End-to-end Guide — Bosch arm64 hardened Vagrant box (Apple Silicon)

**This is the single entry-point doc.** It tells you, from a brand-new
Apple Silicon Mac with nothing installed, how to:

1. Install every tool, library, plugin, and credential you'll need
2. Bake the `bosch/ubuntu2204-cisl1-arm64` image (Stage 1 base + Stage 2 hardened)
3. Smoke-test the box locally — three tiers, increasing realism
4. Publish + release to the HCP Vagrant Registry
5. Validate as a real registry consumer
6. Clean up
7. Diagnose anything that goes wrong — every issue we hit during the 2026-05-20 release is documented with symptom → diagnosis → fix

If a section gets too deep, it cross-references the existing topic-focused docs:
- [`BUILD-WORKFLOW.md`](./BUILD-WORKFLOW.md) — two-stage Packer internals
- [`build-and-publish-runbook.md`](./build-and-publish-runbook.md) — happy-path operational runbook
- [`vagrant-cloud-publish.md`](./vagrant-cloud-publish.md) — registry/publish theory
- [`rebake-bosch-arm64-runbook.md`](./rebake-bosch-arm64-runbook.md) — runbook for re-baking after a fix lands

When this doc and the topic docs disagree, **this doc wins** (it was last revised 2026-05-20 after a full release cycle; the others were last touched 2026-05-07).

---

## Table of contents

- [Quick reference card](#quick-reference-card)
- [Part 0 — Concepts (2-minute mental model)](#part-0--concepts-2-minute-mental-model)
- [Part I — First-time setup](#part-i--first-time-setup)
  - [I.1 Hardware + OS prerequisites](#i1-hardware--os-prerequisites)
  - [I.2 Install macOS dependencies](#i2-install-macos-dependencies)
  - [I.3 Install Vagrant plugins](#i3-install-vagrant-plugins)
  - [I.4 Install Ansible collections](#i4-install-ansible-collections)
  - [I.5 Set up HCP Vagrant Registry auth](#i5-set-up-hcp-vagrant-registry-auth)
  - [I.6 Clone + bootstrap the repo](#i6-clone--bootstrap-the-repo)
  - [I.7 Generate the bake-time SSH keypair](#i7-generate-the-bake-time-ssh-keypair)
- [Part II — Build workflow](#part-ii--build-workflow)
  - [II.1 The two-stage model](#ii1-the-two-stage-model)
  - [II.2 Bake Stage 1 (base — one-time, monthly refresh)](#ii2-bake-stage-1-base--one-time-monthly-refresh)
  - [II.3 Bake Stage 2 (hardened — every release)](#ii3-bake-stage-2-hardened--every-release)
  - [II.4 What gets produced and where](#ii4-what-gets-produced-and-where)
- [Part III — Smoke-test workflow](#part-iii--smoke-test-workflow)
  - [III.1 Tier A — direct QEMU (bypass vagrant)](#iii1-tier-a--direct-qemu-bypass-vagrant)
  - [III.2 Tier B — vagrant integration (consumer parity)](#iii2-tier-b--vagrant-integration-consumer-parity)
  - [III.3 Tier C — registry consumer simulation (post-release only)](#iii3-tier-c--registry-consumer-simulation-post-release-only)
- [Part IV — Publish + Release](#part-iv--publish--release)
  - [IV.1 Auth env preflight](#iv1-auth-env-preflight)
  - [IV.2 Upload (unreleased)](#iv2-upload-unreleased)
  - [IV.3 Release](#iv3-release)
  - [IV.4 Provider-slot semantics — qemu vs libvirt](#iv4-provider-slot-semantics--qemu-vs-libvirt)
- [Part V — Cleanup](#part-v--cleanup)
- [Part VI — Troubleshooting & lessons learned](#part-vi--troubleshooting--lessons-learned)
  - [VI.1 Boot-time issues](#vi1-boot-time-issues)
  - [VI.2 Network-time issues](#vi2-network-time-issues)
  - [VI.3 SSH / auth issues](#vi3-ssh--auth-issues)
  - [VI.4 Packer / template issues](#vi4-packer--template-issues)
  - [VI.5 Vagrant / consumer-side issues](#vi5-vagrant--consumer-side-issues)
  - [VI.6 Registry / publish issues](#vi6-registry--publish-issues)
  - [VI.7 Environment / shell issues](#vi7-environment--shell-issues)
- [Appendix A — File layout](#appendix-a--file-layout)
- [Appendix B — Command cheat sheet](#appendix-b--command-cheat-sheet)
- [Appendix C — Environment variable reference](#appendix-c--environment-variable-reference)
- [Appendix D — Further reading & memory pointers](#appendix-d--further-reading--memory-pointers)

---

## Quick reference card

For someone who's done this before and just needs the commands. Read Part I if it's your first time.

```bash
# ===== Setup (one-time) =====
brew install packer ansible vagrant qemu coreutils jq                # macOS tooling
vagrant plugin install vagrant-qemu                                  # consumer side
ansible-galaxy collection install ansible.posix community.general    # bake-time
# HCP service principal → put creds in ~/.zshrc:
#   export HCP_CLIENT_ID="..."
#   export HCP_CLIENT_SECRET="..."
#   export VAGRANT_CLOUD_ORG="nthedao2705"   # REGISTRY slug, not HCP org slug

# ===== Build =====
cd ~/Projects/Infrastrutures/devops-tools/packer
export NEW_VER=$(date +%F).1
export BASE_VERSION=$(ls -1 output/base/ubuntu2204-arm64/ | sort -r | head -1)
ARCH=arm64 STAGE=hardened BASE_VERSION=$BASE_VERSION \
  ./scripts/build.sh bosch qemu $NEW_VER 2>&1 | tee /tmp/bake-$NEW_VER.log

# ===== Smoke test =====
./smoke/qemu-bosch-arm64/verify-bake-fixes.sh $NEW_VER      # Tier A — direct QEMU
cd smoke/qemu-bosch-arm64 && cp Vagrantfile.stripped Vagrantfile
./smoke/qemu-bosch-arm64/smoke-vagrant.sh                   # Tier B — vagrant integration

# ===== Publish + release =====
./scripts/publish.sh bosch $NEW_VER --providers qemu        # Upload (unreleased)
./scripts/publish.sh bosch $NEW_VER --release               # Flip to released

# ===== Cleanup =====
pkill -KILL -f 'qemu-system' 2>/dev/null
vagrant box remove nthedao2705/ubuntu2204-cisl1-arm64 --all --force 2>/dev/null
rm -rf smoke/qemu-bosch-arm64/.vagrant /tmp/vagrant-qemu-serial.log

# ===== Git =====
git add packer/ && git commit -m "release ${NEW_VER}: <reason>"
git tag -a "bosch-arm64-${NEW_VER}" -m "release notes…"
git push && git push --tags
```

---

## Part 0 — Concepts (2-minute mental model)

**What does this project produce?**
A `.box` file for the [HashiCorp Vagrant Registry](https://portal.cloud.hashicorp.com/) named `nthedao2705/ubuntu2204-cisl1-arm64`. Engineers on Apple Silicon Macs install it via `vagrant init nthedao2705/ubuntu2204-cisl1-arm64; vagrant up --provider qemu` and get a CIS-Level-1-hardened Ubuntu 22.04 ARM64 VM.

**Why so many layers?**
Three reasons:
1. **Hardware**: Apple Silicon is ARM64. macOS only supports Hypervisor.framework natively. VirtualBox arm64 is not Apple-Silicon-friendly. → We standardize on **QEMU + HVF** for arm64.
2. **Vagrant ecosystem mismatch**: HashiCorp doesn't ship an official `qemu` Vagrant plugin. The community `vagrant-qemu` plugin reuses `vagrant-libvirt`'s box format. → We bake `.box` files for the `qemu` provider but tag them with `libvirt` provider on the registry (see [Part IV.4](#iv4-provider-slot-semantics--qemu-vs-libvirt)).
3. **Compliance**: bosch tenant requires CIS Benchmark Level 1 hardening. → Ansible role applied as a second Packer stage on top of the base OS install.

**Two stages, three artifacts per release:**

```
Stage 1 (base, ~15 min, monthly):   ISO → installer → bare Ubuntu 22.04 ARM64 qcow2
                                                       ↓
Stage 2 (hardened, ~3 min, per-release):  base qcow2 → Ansible compliance role → hardened qcow2 + efivars.fd + .box bundle
                                                                                                    ↓
Publish (~3 min):                          .box → HCP Vagrant Registry (provider=libvirt + provider=qemu slots)
```

**Why does the .box need both qemu and libvirt provider slots on the registry?**
When a consumer runs `vagrant up --provider qemu`, the vagrant-qemu plugin internally asks the registry for a `libvirt`-tagged box (format reuse). So a vagrant-qemu consumer needs the libvirt slot. We upload to both for belt-and-braces compatibility with non-vagrant-qemu workflows.

---

## Part I — First-time setup

### I.1 Hardware + OS prerequisites

| Requirement | Why |
|---|---|
| Apple Silicon Mac (M1/M2/M3/M4) | ARM64 host; QEMU + HVF accelerator only works on Apple Silicon |
| macOS 13+ (Ventura or newer) | Hypervisor.framework features used by QEMU 11.x |
| ≥ 30 GB free disk under your project tree | Packer outputs ~4 GB qcow2 + ~1.6 GB .box per release; base image ~5 GB |
| ≥ 8 GB available RAM | Packer's QEMU guest runs with 4 GB by default |
| Homebrew installed | Used for all CLI dependencies |

> ⚠️ **You cannot bake an x86 image on this host.** Stage-1 base bakes use QEMU's HVF accelerator, which only supports same-architecture virtualization. To bake x86 (e.g. for renesas), use a cloud or dedicated x86 host. See memory `project_apple_silicon_x86_baking.md`.

> ⚠️ **Don't keep this repo inside `~/Documents` or `~/Desktop`.** iCloud Drive's "Optimize Mac Storage" will silently evict object files / build outputs and break Packer/Vagrant runs. Canonical location: `~/Projects/Infrastrutures/`. See memory `feedback_icloud_dev_workflow.md`.

### I.2 Install macOS dependencies

```bash
# Core tools
brew install packer            # 1.10.0+ required (we run 1.15.x)
brew install qemu              # 8.0+ required (we run 11.0)
brew install ansible           # 2.14+ required (we run core 2.20)
brew install --cask vagrant    # 2.4.3+ required (we run 2.4.9); --cask because not a Homebrew formula

# Auxiliary tooling
brew install coreutils         # GNU date / mktemp behavior used in scripts
brew install jq                # Used by publish.sh + verify scripts
brew install gnu-tar           # Some scripts use --owner / --group flags; macOS bsdtar lacks them

# Diagnostics (optional but recommended)
brew install socat             # Attach to QEMU monitor sockets when debugging
brew install netcat            # Smoke harness uses `nc` for SSH banner probes
```

Verify each:
```bash
packer version          # >= 1.10.0
qemu-system-aarch64 --version | head -1
ansible --version | head -1
vagrant --version       # >= 2.4.3 for HCP_CLIENT_ID env-var auth
```

### I.3 Install Vagrant plugins

```bash
vagrant plugin install vagrant-qemu     # consumer-side runtime for our .box
vagrant plugin list | grep qemu          # expect: vagrant-qemu (0.3.x+)
```

> ⚠️ **vagrant-qemu 0.3.12 hardcodes the bundled EDK2 NVRAM** and ignores any `qe.firmware_vars` setting in a Vagrantfile. We work around this at bake time by installing GRUB at the UEFI fallback path `/EFI/BOOT/BOOTAA64.EFI`. See [VI.1.1](#vi11-vagrant-up-hangs-at-uefi--ufeibdsdxe-arm-trnglib-image-at--start-failed).

### I.4 Install Ansible collections

```bash
# Required by the bake playbook for cross-distro tasks
ansible-galaxy collection install ansible.posix       # authorized_key, sysctl
ansible-galaxy collection install ansible.builtin     # already present in core
ansible-galaxy collection install community.general   # for some legacy roles
```

Verify:
```bash
ansible-galaxy collection list | grep -E 'ansible.posix|community.general'
# Expect: ansible.posix 1.x+, community.general 7.x+
```

> ⚠️ Don't pin `community.general` to `12.0.0` or higher — the `yaml` stdout callback was removed there. Either pin `< 12.0` or update your `ansible.cfg` to `stdout_callback = ansible.builtin.default` + `result_format = yaml`. See memory `feedback_ansible_yaml_callback_removed.md`.

### I.5 Set up HCP Vagrant Registry auth

The legacy `atlasv1.<token>` style is deprecated. Modern auth uses **HCP IAM service principals**.

**Step 1 — Create the service principal in HCP**

1. Go to https://portal.cloud.hashicorp.com/
2. Pick your org → **Access control (IAM)** → **Service principals** → **Create**
3. Give it a name (e.g. `vagrant-publish-bot`), assign role **Contributor** at the org level
4. Click into the new SP → **Service principal keys** → **Generate new key**
5. **Save `client_id` + `client_secret` immediately** — secret is shown ONCE

**Step 2 — Identify your registry slug** (≠ HCP org slug)

Post-migration, the box-registry slug is the **legacy Vagrant Cloud username**, not the HCP org slug they're now wrapped in. For `nthedao2705-org` (HCP org), the registry slug is `nthedao2705`.

To find yours: HCP portal → org → project → **Vagrant** → **Registries** (column shows the slug).

**Step 3 — Export the env vars**

Add to `~/.zshrc`:
```bash
export HCP_CLIENT_ID="<from step 1.5>"
export HCP_CLIENT_SECRET="<from step 1.5>"
export VAGRANT_CLOUD_ORG="nthedao2705"   # REGISTRY slug, NOT HCP org slug
```

Reload: `source ~/.zshrc`. Verify:
```bash
echo "HCP_CLIENT_ID set?: ${HCP_CLIENT_ID:+yes}"
echo "VAGRANT_CLOUD_ORG: ${VAGRANT_CLOUD_ORG}"
```

> ⚠️ Setting `VAGRANT_CLOUD_ORG` to the HCP org slug (`nthedao2705-org`) produces `Vagrant Cloud request failed - registry not found`. See [VI.6.1](#vi61-vagrant-cloud-request-failed---registry-not-found).

### I.6 Clone + bootstrap the repo

```bash
mkdir -p ~/Projects/Infrastrutures
cd ~/Projects/Infrastrutures
git clone <devops-tools-origin-url> devops-tools
cd devops-tools/packer

# Verify the smoke harness is present (it's gitignored but checked in per-version)
ls -la smoke/qemu-bosch-arm64/ 2>/dev/null || mkdir -p smoke/qemu-bosch-arm64
```

The `smoke/` directory is **gitignored**. If you're cloning fresh, you'll need to recreate the harness scripts — see [`rebake-bosch-arm64-runbook.md`](./rebake-bosch-arm64-runbook.md) or copy them from another team member's tree.

### I.7 Generate the bake-time SSH keypair

The Packer template at `templates/bosch-ubuntu2204-arm64-hardened.pkr.hcl` references `keys/packer_ed25519` (private) and renders `keys/packer_ed25519.pub` into the autoinstall user-data.

If `keys/packer_ed25519` doesn't exist:
```bash
mkdir -p keys
ssh-keygen -t ed25519 -f keys/packer_ed25519 -N '' -C "packer-bake@$(hostname -s)"
chmod 600 keys/packer_ed25519
ls -la keys/  # both files present, private = 600
```

The `keys/` directory is gitignored. **Never commit the private key.**

---

## Part II — Build workflow

### II.1 The two-stage model

The build is split into two Packer runs:

| Stage | Template | Input | Output | Time |
|---|---|---|---|---|
| **1 — base** | `templates/ubuntu2204-arm64-base.pkr.hcl` | Ubuntu 22.04 ARM64 server ISO | `output/base/ubuntu2204-arm64/<base-version>/*.qcow2` + `efivars.fd` | ~12–15 min (autoinstall) |
| **2 — hardened** | `templates/bosch-ubuntu2204-arm64-hardened.pkr.hcl` | The base qcow2 | `output/bosch/arm64/qemu/<image-version>/*.box` + `.qcow2` + `efivars.fd` | ~3 min (Ansible only) |

See [`BUILD-WORKFLOW.md`](./BUILD-WORKFLOW.md) for the in-depth model + diagrams.

### II.2 Bake Stage 1 (base — one-time, monthly refresh)

You only need Stage 1 if:
- You have NO base image yet (`ls output/base/ubuntu2204-arm64/` is empty)
- You want to refresh against a newer Ubuntu point release
- A CVE forces a rebuild of the underlying OS image

Otherwise skip to Stage 2.

```bash
cd ~/Projects/Infrastrutures/devops-tools/packer

ARCH=arm64 STAGE=base \
  ./scripts/build.sh bosch qemu 2>&1 | tee /tmp/bake-base-$(date +%F).log

# Outputs land at:
ls -la output/base/ubuntu2204-arm64/$(date +%F)/
# expect: *.qcow2 (~5 GB), efivars.fd (64 MB), manifest.json
```

### II.3 Bake Stage 2 (hardened — every release)

This is what you run for every new release. ~3 min.

```bash
cd ~/Projects/Infrastrutures/devops-tools/packer

# Pick a release version (YYYY-MM-DD.N)
export NEW_VER=$(date +%F).1

# Auto-detect the most recent base image
export BASE_VERSION=$(ls -1 output/base/ubuntu2204-arm64/ | sort -r | head -1)
echo "BASE_VERSION=$BASE_VERSION"

# Bake
ARCH=arm64 STAGE=hardened \
  BASE_VERSION="$BASE_VERSION" \
  ./scripts/build.sh bosch qemu "$NEW_VER" 2>&1 | tee /tmp/bake-$NEW_VER.log
```

**Watch for these success signals in the log:**

| Marker | Meaning |
|---|---|
| `==> qemu.bosch-ubuntu2204-arm64: Booting from disk` | Stage-2 VM boots off the base qcow2 |
| `PLAY [Bake hardened base image]` | Ansible kicks off |
| `TASK [Bake \| install GRUB shim at UEFI fallback path...]` → `changed` | **Fix #1** applied (UEFI fallback) |
| `TASK [Bake \| authorize Vagrant's well-known insecure RSA pubkey...]` → `changed` | **Fix #3** applied (vagrant key) |
| `PLAY RECAP` → `failed=0 unreachable=0` | Ansible clean |
| `Running post-processor: shell-local` → `tar -tzf` listing **4 files** | **Fix #4** applied (shell-local PP) |
| `Builds finished. The artifacts of successful builds are:` | DONE |

If any signal is missing, jump to [Part VI Troubleshooting](#part-vi--troubleshooting--lessons-learned).

### II.4 What gets produced and where

```
packer/output/bosch/arm64/qemu/<image-version>/
├── bosch-ubuntu2204-cisl1-arm64-<image-version>.box      # ~1.4 GB — what gets uploaded
├── bosch-ubuntu2204-cisl1-arm64-<image-version>.qcow2    # ~4 GB — raw VM disk
├── efivars.fd                                             # 64 MB — UEFI NVRAM
└── manifest.json                                          # Packer manifest
```

**Verify the .box bundle structure**:
```bash
tar -tzf output/bosch/arm64/qemu/$NEW_VER/bosch-ubuntu2204-cisl1-arm64-$NEW_VER.box
# expect EXACTLY:
#   metadata.json
#   Vagrantfile
#   box.img
#   efivars.fd

tar -xzOf output/bosch/arm64/qemu/$NEW_VER/bosch-ubuntu2204-cisl1-arm64-$NEW_VER.box metadata.json
# expect: {"provider":"libvirt","format":"qcow2","architecture":"arm64","virtual_size":40}
```

If the bundle is missing `efivars.fd` or metadata.json says `provider:qemu`: see [VI.4.2](#vi42-shell-local-pp-produces-wrong-metadatajson-or-misses-efivarsfd).

---

## Part III — Smoke-test workflow

Three tiers, increasing realism. **Run them in order — each rules in/out a different layer.**

The harness lives at `packer/smoke/qemu-bosch-arm64/`:

```
smoke/qemu-bosch-arm64/
├── Vagrantfile                      # Active Vagrantfile (swap content between releases)
├── Vagrantfile.stripped             # Minimal consumer-style Vagrantfile (the post-bake target)
├── Vagrantfile.with-workarounds     # Pre-fix Vagrantfile with NVRAM trigger + build-key (legacy)
├── smoke-manual.sh                  # Tier A — bypass vagrant, boot qcow2 directly
├── smoke-vagrant.sh                 # Tier B — end-to-end vagrant up against local .box
├── verify-bake-fixes.sh             # Tier A++ — boot with EMPTY NVRAM, verify all 3 bake fixes
├── probe-ssh-with-build-key.sh      # Diagnostic — in-guest inspection via build-time key
├── probe-authkeys.exp               # Diagnostic — serial-console login via expect
└── probe-ssh-keys.sh                # Diagnostic — try each available ssh key with -v
```

### III.1 Tier A — direct QEMU (bypass vagrant)

Proves the **qcow2 is sound** independent of vagrant-qemu plugin quirks.

```bash
cd ~/Projects/Infrastrutures/devops-tools/packer
./smoke/qemu-bosch-arm64/verify-bake-fixes.sh $NEW_VER
```

🚦 **Pass criterion**:
```
[PASS] F2 — virtio-net-pci → NIC is enp0sN (matches netplan en*)
[PASS] F1 — EFI fallback path baked in (/EFI/BOOT/BOOTAA64.EFI exists)
[PASS] F3 — vagrant insecure RSA pubkey is in /home/packer/.ssh/authorized_keys
==================== 3/3 bake fixes confirmed ====================
```

This script deliberately **boots with an empty NVRAM** to prove the EFI fallback works. If F1 fails, the box would brick on consumer machines.

### III.2 Tier B — vagrant integration (consumer parity)

Proves a real consumer's `vagrant up --provider qemu` works **with no workarounds**.

```bash
cd ~/Projects/Infrastrutures/devops-tools/packer/smoke/qemu-bosch-arm64

# Use the stripped (no-workarounds) Vagrantfile
cp Vagrantfile.stripped Vagrantfile

# Clean state
pkill -KILL -f 'qemu-system' 2>/dev/null; sleep 2
rm -rf .vagrant
vagrant box remove nthedao2705/ubuntu2204-cisl1-arm64 --all --force 2>/dev/null

# Add box from local .box file
vagrant box add --force --name nthedao2705/ubuntu2204-cisl1-arm64 \
  /Users/thedao/Projects/Infrastrutures/devops-tools/packer/output/bosch/arm64/qemu/$NEW_VER/bosch-ubuntu2204-cisl1-arm64-$NEW_VER.box \
  --provider libvirt --architecture arm64

# Boot
vagrant up --provider qemu

# SSH proof
vagrant ssh -c 'cat /etc/image-metadata | grep image_version'

# Cleanup
vagrant halt && vagrant destroy -f
```

🚦 **Pass criterion**: `Machine booted and ready!` + `image_version=<NEW_VER>`. The first-boot sequence should also show `Vagrant insecure key detected. Vagrant will automatically replace...` followed by `Key inserted!` — this proves Fix #3 (the vagrant-key authorization) is working.

### III.3 Tier C — registry consumer simulation (post-release only)

Run this **after** publish + release ([Part IV](#part-iv--publish--release)). Proves a fresh engineer with no local cache can pull and boot.

```bash
SIM=$(mktemp -d -t consumer-sim-XXXX); cd "$SIM"
vagrant box remove nthedao2705/ubuntu2204-cisl1-arm64 --all --force 2>/dev/null

# HCP auth must be in env for private-box pull
eval "$(grep -E '^export (HCP_CLIENT_ID|HCP_CLIENT_SECRET|VAGRANT_CLOUD_ORG)=' ~/.zshrc | sed 's/^export //')"
export HCP_CLIENT_ID HCP_CLIENT_SECRET VAGRANT_CLOUD_ORG

cat > Vagrantfile <<'EOF'
Vagrant.configure("2") do |config|
  config.vm.box              = "nthedao2705/ubuntu2204-cisl1-arm64"
  config.vm.box_architecture = "arm64"
  config.vm.synced_folder ".", "/vagrant", disabled: true
  config.vm.boot_timeout     = 300
end
EOF

vagrant up --provider qemu
vagrant ssh -c 'cat /etc/image-metadata | grep image_version'
vagrant halt && vagrant destroy -f
cd /tmp && rm -rf "$SIM"
```

🚦 **Pass criterion**: vagrant downloads from `https://vagrantcloud.com/.../providers/libvirt/arm64/vagrant.box` AND `vagrant up` reaches `Machine booted and ready!`. If you get a 404 or "Requested provider: libvirt" mismatch, see [VI.6.2](#vi62-vagrant-up-from-registry-says-box-doesnt-support-provider-libvirt).

---

## Part IV — Publish + Release

### IV.1 Auth env preflight

```bash
echo "HCP_CLIENT_ID:     ${HCP_CLIENT_ID:+set (len=${#HCP_CLIENT_ID})}"
echo "HCP_CLIENT_SECRET: ${HCP_CLIENT_SECRET:+set (len=${#HCP_CLIENT_SECRET})}"
echo "VAGRANT_CLOUD_ORG: ${VAGRANT_CLOUD_ORG:-(unset)}"
```

🔀 If unset → source from `~/.zshrc` (Setup [I.5](#i5-set-up-hcp-vagrant-registry-auth)).
🔀 If `VAGRANT_CLOUD_ORG` is your HCP org slug instead of the registry slug → fix it now. See [VI.6.1](#vi61-vagrant-cloud-request-failed---registry-not-found).

### IV.2 Upload (unreleased)

```bash
cd ~/Projects/Infrastrutures/devops-tools/packer
./scripts/publish.sh bosch $NEW_VER --providers qemu 2>&1 \
  | tee /tmp/publish-$NEW_VER.log
```

The script does four things in order:
1. Ensure box `<org>/<name>` exists (idempotent)
2. Ensure version `<NEW_VER>` exists (creates as `unreleased`)
3. For each provider: ensure provider slot exists + upload .box file
4. (Optionally, if `--release` given) flip version state to `released`

**Modern `publish.sh` (2026-05-20+) auto-mirrors qemu uploads to a libvirt slot** — the same .box file is uploaded under both `qemu` and `libvirt` provider names. This is required because the vagrant-qemu consumer plugin queries the registry for `libvirt`-tagged boxes (see [IV.4](#iv4-provider-slot-semantics--qemu-vs-libvirt)).

🚦 **Watch for these signals:**
- `==> auth: HCP service principal` — auth path confirmed
- `Created version <NEW_VER> ... Status: unreleased`
- `Uploaded provider qemu` AND `Uploaded provider libvirt` (both slots)
- `==> done.`

🔀 If `An invalid option was specified` on upload — see [VI.6.3](#vi63-vagrant-cloud-provider-upload---an-invalid-option-was-specified).
🔀 If `Failed to create box ... registry not found` — see [VI.6.1](#vi61-vagrant-cloud-request-failed---registry-not-found).

### IV.3 Release

After Tier B passes:

```bash
./scripts/publish.sh bosch $NEW_VER --release
```

This re-runs the full publish pipeline (box→version→providers→upload→release). It's safe — every step is idempotent. The release step uses `vagrant cloud version release --force` to bypass the interactive TTY prompt.

🚦 **Pass criterion**: `Released version <NEW_VER> on nthedao2705/ubuntu2204-cisl1-arm64`. Verify externally:
```bash
vagrant cloud box show nthedao2705/ubuntu2204-cisl1-arm64
# expect: Current Version: <NEW_VER>
```

Then run [Tier C](#iii3-tier-c--registry-consumer-simulation-post-release-only) to prove the release is consumable.

### IV.4 Provider-slot semantics — qemu vs libvirt

This is the trickiest part of the publish — three different "provider" identifiers live in three different places, and they don't all agree:

| Layer | Identifier value | Purpose |
|---|---|---|
| `metadata.json` inside the `.box` | **`libvirt`** | Identifies box FORMAT (vagrant-libvirt v1 layout) — what `vagrant box add` looks at |
| Registry / HCP provider slot | **`libvirt`** + **`qemu`** (we upload to BOTH) | API-level name. `vagrant up --provider qemu` consumers cause the vagrant-qemu plugin to query the `libvirt` slot. Some workflows do `vagrant box add --provider qemu` directly — they hit the `qemu` slot. Belt-and-braces: upload to both. |
| Embedded Vagrantfile (`config.vm.provider`) inside the `.box` | **`:qemu`** | Which consumer-side provider plugin to activate. This is the ONE place `qemu` appears. |

If you set `metadata.json`'s `provider` to `qemu` (looks intuitive) → `vagrant up` says "Box could not be found. Requested provider: libvirt" → 🩹 see [VI.5.3](#vi53-the-box-youre-attempting-to-add-doesnt-support-the-provider-you-requested).

If you only upload to provider=qemu on the registry → fresh-cache `vagrant up --provider qemu` against the registry returns 404 → 🩹 see [VI.6.2](#vi62-vagrant-up-from-registry-says-box-doesnt-support-provider-libvirt).

---

## Part V — Cleanup

```bash
# 1. Stop any orphaned QEMU processes
pkill -KILL -f 'qemu-system' 2>/dev/null

# 2. Clean local vagrant box cache (force re-download next time)
vagrant box remove nthedao2705/ubuntu2204-cisl1-arm64 --all --force 2>/dev/null

# 3. Clean smoke-test state
cd ~/Projects/Infrastrutures/devops-tools/packer/smoke/qemu-bosch-arm64
rm -rf .vagrant /tmp/vagrant-qemu-serial.log
rm -rf verify-run manual-run buildkey-run authkeys-run probe-run stage  # ephemeral subdirs

# 4. OPTIONAL: archive old build outputs
# (Don't blindly nuke — the .qcow2 + efivars.fd are the heavy bake artifacts.
#  If you might need to repack the .box, KEEP these. If you've got the .box
#  uploaded and tagged, you can delete the qcow2 to reclaim ~4 GB per release.)
ls -la ~/Projects/Infrastrutures/devops-tools/packer/output/bosch/arm64/qemu/

# 5. Backup files (smoke harness leaves .bak2)
find ~/Projects/Infrastrutures/devops-tools/packer/output -name '*.bak*'
# Decide whether to keep or remove
```

---

## Part VI — Troubleshooting & lessons learned

Every issue we hit during the 2026-05-05 → 2026-05-20 release cycle is documented here. Organized by layer.

### VI.1 Boot-time issues

#### VI.1.1 `vagrant up` hangs at UEFI — `ArmTrngLib`, `Image at … start failed`

**Symptom**: serial log shows:
```
ArmTrngLib could not be correctly initialized.
Error: Image at 000BFDB6000 start failed: 00000001
Error: Image at 000BFD6D000 start failed: Not Found
Tpm2SubmitCommand - Tcg2 - Not Found
```
…then nothing. No GRUB, no kernel.

**Diagnosis**: UEFI initialized but can't find a bootloader. Two layers can cause this:

1. **Empty NVRAM**: Ubuntu's installer writes the `Boot0001 → /EFI/ubuntu/grubaa64.efi` entry to NVRAM. vagrant-qemu 0.3.x **hardcodes a copy of an empty NVRAM file** and ignores any `qe.firmware_vars` setting, so consumers get UEFI with no boot entries.
2. **No fallback EFI binary**: If the qcow2 doesn't have `/EFI/BOOT/BOOTAA64.EFI` (UEFI's removable-media fallback path), there's nothing for UEFI to fall back to.

**Fix (bake-time)**: We added an Ansible post-task that copies `shimaa64.efi` → `BOOTAA64.EFI`, making the box NVRAM-independent:
```yaml
- name: "Bake | install GRUB shim at UEFI fallback path so empty-NVRAM boots work"
  ansible.builtin.copy:
    src: /boot/efi/EFI/ubuntu/shimaa64.efi
    dest: /boot/efi/EFI/BOOT/BOOTAA64.EFI
    remote_src: true
    owner: root
    group: root
    mode: "0755"
```

See `playbooks/packer-bake.yml` for the actual task. **Verify by running `./smoke/qemu-bosch-arm64/verify-bake-fixes.sh` — it boots the qcow2 with a wiped NVRAM specifically to prove this path works.**

#### VI.1.2 QEMU display shows monitor REPL instead of guest boot

**Symptom**: when running QEMU manually with a window (`-display cocoa`), you see the QEMU monitor command prompt, not the guest boot. Keystrokes go to monitor instead of GRUB.

**Diagnosis**: aarch64 virt machine has NO default graphics device. You need to explicitly add `ramfb` + `virtio-gpu-pci`.

**Fix**: in your manual QEMU launch:
```bash
qemu-system-aarch64 ... -device ramfb -device virtio-gpu-pci -display cocoa
```

Packer's template already handles this (look in `qemuargs`). See memory `feedback_packer_qemu_aarch64_no_default_gfx.md`.

#### VI.1.3 `headless = false` fails with "no display" on macOS

**Symptom**: Packer fails with display-related errors when `headless = false`.

**Diagnosis**: vagrant-qemu / Packer's qemu plugin defaults to `-display gtk`. Homebrew qemu on macOS has no GTK support.

**Fix**: override in `qemuargs` to use `-display cocoa`:
```hcl
qemuargs = [
  ["-display", "cocoa"],
  ...
]
```

See memory `feedback_packer_qemu_macos_display.md`.

### VI.2 Network-time issues

#### VI.2.1 VM boots fully but no SSH banner — NIC is DOWN

**Symptom**: QEMU process is running, port forward is up (`nc -z 127.0.0.1 50022` succeeds), but SSH `Connection timed out during banner exchange`. Serial log shows full systemd start including `Started OpenBSD Secure Shell server`.

**Diagnosis**: Inside the guest, run `ip -brief link`. If you see only:
```
lo               UNKNOWN   ...  <LOOPBACK,UP,LOWER_UP>
eth0             DOWN      ...  <BROADCAST,MULTICAST>
```

…then the NIC is named `eth0` (legacy fallback) and netplan's `match: name: en*` (predictable PCI naming) doesn't match it → DHCP never runs → external network is dead → sshd has no interface to bind to other than `lo`.

**Root cause**: vagrant-qemu 0.3.x defaults `net_device` to `virtio-net-device`, which uses **virtio-mmio** bus. Aarch64 guests on the mmio bus name NICs `eth0` (legacy). Packer's bake-time qemu used `virtio-net` (PCI), giving `enp0sN`. Bake-time worked → netplan match worked → DHCP fine. Consumer-time mismatch.

**Fix (bake-time)**: in `templates/box-vagrantfile.qemu.rb` (the embedded Vagrantfile shipped INSIDE the .box):
```ruby
qe.net_device = 'virtio-net-pci'   # NOT 'virtio-net-device'
```

This puts the NIC on the PCIe bus → guest names it `enp0s1` → netplan matches → DHCP runs.

#### VI.2.2 SMB synced folder hangs at "Username (user[@domain])"

**Symptom**: After `vagrant up --provider qemu` on macOS, prompt:
```
==> default: Preparing SMB shared folders...
    default: Username (user[@domain]): packer
    default: Password (will be hidden): 
Vagrant SMB synced folders require the account password to be stored
in an NT compatible format. Please update your sharing settings...
```

**Diagnosis**: vagrant-qemu on macOS defaults to SMB for `/vagrant`. macOS removed "Windows File Sharing" from the default System Settings UI, so SMB auth fails.

**Fix**: disable the synced folder in your consumer Vagrantfile:
```ruby
config.vm.synced_folder ".", "/vagrant", disabled: true
```

Or, if you need file sync, use `type: "rsync"` instead of the default SMB. See [`Vagrantfile.stripped`](../smoke/qemu-bosch-arm64/Vagrantfile.stripped) for the canonical consumer pattern.

### VI.3 SSH / auth issues

#### VI.3.1 `Permission denied (publickey)` despite VM booted

**Symptom**: VM boots, SSH banner appears, but auth fails with all of Vagrant's bundled keys:
```
ssh -i ~/.vagrant.d/insecure_private_keys/vagrant.key.rsa -p 50022 packer@127.0.0.1
> Permission denied (publickey).
```

**Diagnosis**: SSH into the guest with the **bake-time** key (`packer/keys/packer_ed25519`) and inspect:
```bash
cat /home/packer/.ssh/authorized_keys
```

If you see only the bake-time ed25519 fingerprint and **NOT** Vagrant's well-known insecure RSA pubkey, this is **Subiquity dropping the 2nd entry** in the autoinstall `ssh.authorized-keys` list. We had this entry in `http/user-data.tmpl`:
```yaml
authorized-keys:
  - "ssh-ed25519 ... packer-bake@..."     # first entry — lands
  - "ssh-rsa ... vagrant insecure public key"  # second entry — silently dropped by Subiquity
```

Only the first one lands.

**Fix (bake-time)**: don't rely on Subiquity. Inject via Ansible:
```yaml
- name: "Bake | authorize Vagrant's well-known insecure RSA pubkey for the bake user"
  ansible.posix.authorized_key:
    user: packer
    state: present
    key: "ssh-rsa AAAAB3NzaC1yc2EAAAABIwAAAQEA...vagrant insecure public key"
```

The Vagrant insecure key is **public knowledge** — HashiCorp ships it with every Vagrant install. Baking it in is safe; Vagrant's default `insert_key = true` replaces it with a generated keypair on first boot anyway.

#### VI.3.2 `vagrant.key.rsa` reported as `type -1` by OpenSSH

**Symptom**:
```
debug1: identity file /Users/thedao/.vagrant.d/insecure_private_keys/vagrant.key.rsa type -1
debug1: identity file /Users/thedao/.vagrant.d/insecure_private_keys/vagrant.key.rsa-cert type -1
```

**Diagnosis**: OpenSSH ≥ 9.x in some macOS builds rejects keys with permissions broader than 600.

**Fix**: `chmod 600 ~/.vagrant.d/insecure_private_keys/vagrant.key.rsa`. Don't `chmod 644` even if it nags.

### VI.4 Packer / template issues

#### VI.4.1 Packer `validate` errors on multi-source templates with `-only=X`

**Symptom**: Even when you pass `-only=qemu.bosch-ubuntu2204-arm64`, `packer validate` still fails because it can't render the other source's variables.

**Diagnosis**: `packer validate` runs against ALL sources regardless of `-only`. Wrapper scripts must always provide non-empty placeholders for every required var.

**Fix**: pass `BASE_IMAGE_PATH=UNUSED` / `BASE_OVA_PATH=UNUSED` in `build.sh`. The actual build (`-only` flag at `packer build`) will skip the unused source.

See memory `feedback_packer_validate_runs_all_sources.md`.

#### VI.4.2 shell-local PP produces wrong `metadata.json` or misses `efivars.fd`

**Symptom**: After bake, `tar -tzf bosch-*.box` shows only 3 files (no `efivars.fd`), or `metadata.json` says `"provider":"qemu"`, or `virtual_size:0`.

**Diagnosis**: The shell-local post-processor in `templates/bosch-ubuntu2204-arm64-hardened.pkr.hcl` is producing a stale bundle. The 2026-05-20 fix dynamically parses qcow2 virtual size from `qemu-img info` and bundles `efivars.fd`.

**Fix**: confirm your template has these lines:
```hcl
"test -f efivars.fd || { echo \"missing efivars.fd\" >&2; exit 1; }",
"VSIZE_GB=$(qemu-img info \"$QCOW2_NAME\" | awk '/virtual size:/{print $3; exit}')",
"printf '{\"provider\":\"libvirt\",\"format\":\"qcow2\",\"architecture\":\"arm64\",\"virtual_size\":%d}\\n' \"$VSIZE_GB\" > \"$stage/metadata.json\"",
"tar -czf \"$BOX_NAME\" -C \"$stage\" metadata.json Vagrantfile box.img efivars.fd",
```

#### VI.4.3 `path.root` produces `templates/templates/box-vagrantfile.qemu.rb` (double prefix)

**Symptom**: shell-local PP fails with:
```
+ test -f templates/templates/box-vagrantfile.qemu.rb
missing templates/templates/box-vagrantfile.qemu.rb
+ exit 1
```

**Diagnosis**: In Packer 1.15.x, `${path.root}` evaluates to the directory containing the .pkr.hcl file — which IS already `templates/`. So `${path.root}/templates/foo` resolves to `templates/templates/foo`.

This is a **change in Packer between 1.10 and 1.15**. The original template was written when `path.root` resolved to the parent dir.

**Fix**: drop the extra `templates/` prefix in the env var:
```hcl
"VAGRANTFILE_TEMPLATE=${path.root}/box-vagrantfile.qemu.rb",
```

#### VI.4.4 Packer + QEMU user-mode net — `{{ .HTTPIP }}` wrong from guest's POV

**Symptom**: Autoinstall never starts; tiny final qcow2 (~100 MB instead of expected ~4 GB).

**Diagnosis**: Packer's `boot_command` uses `{{ .HTTPIP }}` for the autoinstall URL, but with QEMU user-mode networking (SLIRP), the guest can only reach the host at the SLIRP gateway IP `10.0.2.2`. `.HTTPIP` is the host's external IP — invisible to the guest.

**Fix**: hardcode `10.0.2.2:{{ .HTTPPort }}` in the boot command for QEMU. See memory `feedback_packer_qemu_user_mode_httpip.md`.

#### VI.4.5 Packer HCL2 — `{{.Provider}}` doesn't work in `locals`

**Symptom**: HCL `locals` block renders `<no value>` instead of the provider name.

**Diagnosis**: Legacy Packer v1 template tokens (`{{.Foo}}`) don't fire in HCL2 `locals`. Use HCL interpolation (`${...}`) instead.

**Fix**: `${source.type}` not `{{.Provider}}`. See memory `feedback_packer_hcl2_provider_token.md`.

#### VI.4.6 Packer qemu `qemuargs` doesn't stack — multi-entry-same-flag REPLACES

**Symptom**: You added a single `["-device", "..."]` to `qemuargs` expecting it to merge with the plugin's defaults; instead the plugin's defaults are gone.

**Diagnosis**: `qemuargs` is a flag-keyed override. If you provide ANY entry for a flag like `-device`, ALL the plugin's defaults for that flag are replaced. You must re-list the defaults you want to keep.

**Fix**: re-list all defaults explicitly:
```hcl
qemuargs = [
  ["-device", "virtio-net,netdev=user.0"],  # plugin default — re-listed
  ["-device", "qemu-xhci"],                  # plugin default — re-listed
  ["-device", "usb-kbd"],                    # your addition
  ["-device", "usb-tablet"],                 # your addition
  ["-device", "ramfb"],                      # your addition
  ["-device", "virtio-gpu-pci"],             # your addition
]
```

See memory `feedback_packer_qemuargs_merge.md`.

### VI.5 Vagrant / consumer-side issues

#### VI.5.1 `vagrant up` boot timeout — VM seems to start but Vagrant gives up

**Symptom**: After ~5 min (or whatever `boot_timeout` is set to):
```
Timed out while waiting for the machine to boot.
```

**Diagnosis tree**:
1. **QEMU still running?** `ps -ef | grep qemu-system | grep -v grep`. If yes, the VM is alive but Vagrant couldn't reach it.
2. **Port forward up?** Check `-netdev user,...hostfwd=tcp::PORT-:22` in QEMU's command line.
3. **TCP reachable?** `nc -zv 127.0.0.1 50022`. If "Connection refused" → guest sshd not started (boot wedged or sshd dead).
4. **TCP open but no SSH banner?** Either guest networking broke ([VI.2.1](#vi21-vm-boots-fully-but-no-ssh-banner--nic-is-down)) or sshd misconfigured.
5. **SSH banner but auth fails?** [VI.3.1](#vi31-permission-denied-publickey-despite-vm-booted).

**Defensive fix**: bump boot_timeout to give cloud-init breathing room:
```ruby
config.vm.boot_timeout = 600  # 10 min — CIS-hardened boxes take longer first-boot
```

#### VI.5.2 Stale QEMU after vagrant timeout blocks next boot — port collision

**Symptom**: Second `vagrant up` fails with:
```
Vagrant cannot forward the specified ports on this VM, since they
would collide with some other application... The forwarded port to 50022
is already in use on the host machine.
```

**Diagnosis**: `vagrant destroy` doesn't always reap the QEMU child cleanly when boot timed out.

**Fix**:
```bash
pkill -INT  -f 'qemu-system' 2>/dev/null
sleep 2
pkill -KILL -f 'qemu-system' 2>/dev/null
lsof -nP -iTCP:50022 -sTCP:LISTEN   # should be empty
```

Drop this in `~/.zshrc` for convenience:
```bash
vagrant_qemu_nuke() {
  pkill -INT  -f 'qemu-system' 2>/dev/null
  sleep 2
  pkill -KILL -f 'qemu-system' 2>/dev/null
  rm -rf .vagrant 2>/dev/null
}
```

#### VI.5.3 "The box you're attempting to add doesn't support the provider you requested"

**Symptom**:
```
==> default: Box 'nthedao2705/ubuntu2204-cisl1-arm64' could not be found.
    default: Box Provider: libvirt
The box you're attempting to add doesn't support the provider you requested.
Requested provider: libvirt
```

**Diagnosis**: Two possible causes:
1. **metadata.json mismatch**: Your local .box has `metadata.json` with `"provider":"qemu"` but vagrant-qemu plugin asks for `libvirt`. Fix: rewrite metadata.json to use `provider:libvirt`. The current `templates/bosch-ubuntu2204-arm64-hardened.pkr.hcl` shell-local PP does this correctly.
2. **Registry slot mismatch**: You uploaded only as `provider=qemu` and a consumer running `vagrant up --provider qemu` tries to pull → registry returns 404 because the consumer's vagrant-qemu plugin queries the `libvirt` slot. Fix: upload to BOTH `qemu` and `libvirt` slots. The current `publish.sh` auto-mirrors qemu → libvirt.

#### VI.5.4 `vagrant box add --provider qemu` when local file has metadata.json provider=libvirt

**Symptom**: You explicitly pass `--provider qemu` to `vagrant box add` for a local file, but Vagrant adds it under `provider=libvirt` anyway.

**Diagnosis**: When adding a local file, Vagrant reads `metadata.json` inside the .box and stores under whatever provider that file declares. The `--provider` CLI flag only matters when adding from a URL where multiple providers might be returned.

**Fix**: don't fight it. Use `--provider libvirt` when adding our local .box files:
```bash
vagrant box add --force --name <org>/<box> ./file.box --provider libvirt --architecture arm64
```

#### VI.5.5 EOF doesn't terminate heredoc — stuck at `heredoc>` prompt

**Symptom**: After pasting a `cat > file <<'EOF' ... EOF` block in zsh, the shell keeps showing `heredoc>` and won't run the command.

**Diagnosis**: Closing `EOF` has leading whitespace. Heredoc terminators must be **flush at column 1**.

**Fix**: paste the block again with `EOF` at column 1, or use `<<-EOF` (which strips leading TABS but NOT spaces). If zsh auto-indent inserts spaces, switch to `printf` or use an editor instead.

### VI.6 Registry / publish issues

#### VI.6.1 `Vagrant Cloud request failed - registry not found`

**Symptom**:
```
Failed to create box nthedao2705-org/ubuntu2204-cisl1-arm64
Vagrant Cloud request failed - registry not found
```

**Diagnosis**: `VAGRANT_CLOUD_ORG` is set to the HCP org slug (`nthedao2705-org`) instead of the registry slug (`nthedao2705`).

**Fix**: in `~/.zshrc`:
```bash
export VAGRANT_CLOUD_ORG="nthedao2705"   # legacy Vagrant Cloud username, NOT HCP org slug
```

To find your registry slug: HCP portal → org → project → Vagrant → Registries (column).

See memory `feedback_vagrant_cloud_hcp_auth.md`.

#### VI.6.2 `vagrant up` from registry says "Box doesn't support provider: libvirt"

**Symptom**: After `vagrant init nthedao2705/ubuntu2204-cisl1-arm64` and `vagrant up --provider qemu`:
```
URL: ["https://vagrantcloud.com/nthedao2705/ubuntu2204-cisl1-arm64"]
Error: The requested URL returned error: 404
```
…or…
```
The box you're attempting to add doesn't support the provider you requested.
Requested provider: libvirt
```

**Diagnosis**: The vagrant-qemu plugin internally asks the registry for a `libvirt`-tagged box. If you only uploaded under `provider=qemu`, the consumer can't find it.

**Fix**: upload to BOTH slots. The current `publish.sh` does this automatically by expanding `qemu` to `qemu + libvirt`. To manually fix an already-uploaded box:
```bash
vagrant cloud provider create  <box> libvirt <version> --architecture arm64
vagrant cloud provider upload  <box> libvirt <version> arm64 <file>.box
```

#### VI.6.3 `vagrant cloud provider upload` — "An invalid option was specified"

**Symptom**:
```
$ vagrant cloud provider upload <box> qemu <version> <file>.box --architecture arm64
An invalid option was specified.
Usage: vagrant cloud provider upload [options] organization/box-name provider-name version architecture box-file
```

**Diagnosis**: `architecture` is now a **POSITIONAL** argument (the 4th), not a `--architecture` flag. Older publish scripts and HashiCorp docs got this wrong.

**Fix**: correct order:
```bash
vagrant cloud provider upload <box> <provider> <version> <architecture> <file>.box
```

Note `provider create` STILL accepts `--architecture` as a flag. The two sibling subcommands have **inconsistent signatures** in Vagrant 2.4.x.

See memory `feedback_vagrant_cloud_cli_24x_signatures.md`.

#### VI.6.4 `vagrant cloud version show` / `provider show` false-positive any probe

**Symptom**: A probe-then-create script does this:
```bash
if vagrant cloud version show <box> <version>; then
  echo "exists — skip"
else
  vagrant cloud version create ...
fi
```
…and the skip branch ALWAYS runs, so the version never gets created.

**Diagnosis**: `vagrant cloud version show` and `vagrant cloud provider show` **DO NOT EXIST** in Vagrant 2.4.x. Invoking them prints the parent subcommand's help and exits 0 — which any probe interprets as "exists."

**Fix**: drop the probe. Just call `create` and tolerate the "already exists" error:
```bash
create_idempotent() {
  local logf=$(mktemp -t vc.XXXXXX); local rc=0
  "$@" >"$logf" 2>&1 || rc=$?
  cat "$logf"
  if [[ $rc -eq 0 ]]; then rm -f "$logf"; return 0; fi
  if grep -qiE 'already exists|has already been taken|status code 422' "$logf"; then
    echo "    (already exists — tolerated)"
    rm -f "$logf"; return 0
  fi
  rm -f "$logf"; return $rc
}
```

`vagrant cloud box show` STILL exists and works fine — keep that probe pattern for box-level checks only.

#### VI.6.5 `vagrant cloud version release` hangs at TTY prompt

**Symptom**: Release step in `publish.sh` shows:
```
This will release version 2026-05-20.1 from <box> to Vagrant Cloud...
Vagrant is attempting to interface with the UI in a way that requires
a TTY. Most actions in Vagrant that require a TTY have configuration
switches to disable this requirement.
```

**Diagnosis**: `vagrant cloud version release` defaults to an interactive `[y/N]` confirmation prompt. publish.sh doesn't auto-answer.

**Fix**: pass `--force`:
```bash
vagrant cloud version release --force <box> <version>
```

The current `publish.sh` (2026-05-20+) already does this.

### VI.7 Environment / shell issues

#### VI.7.1 macOS bash 3.2 + `set -u` + empty array

**Symptom**: A script using `set -u` (treat unset as error) breaks on `"${arr[@]}"` when the array is empty:
```
./script.sh: line N: arr[@]: unbound variable
```

**Diagnosis**: Apple bash is forever 3.2.57. Strict mode treats empty `${arr[@]}` as unset.

**Fix**: use the `+` substitution guard:
```bash
"${arr[@]+"${arr[@]}"}"   # safe under set -u even when arr is empty
```

See memory `feedback_bash_strict_empty_array.md`.

#### VI.7.2 macOS bash 3.2 — no associative arrays

**Symptom**: `declare -A: invalid option`.

**Diagnosis**: `declare -A` (associative arrays) requires bash 4.0+. Apple bash is 3.2.

**Fix**: use a delimited-string set membership pattern:
```bash
ALLOWED_STR=""
for p in foo bar; do
  ALLOWED_STR="${ALLOWED_STR}|${p}|"
done
contains() { [[ "${ALLOWED_STR}" == *"|${1}|"* ]]; }
contains foo && echo yes
```

#### VI.7.3 `PACKER_LOG_PATH` directory doesn't exist

**Symptom**:
```
==> packer: failed to open log file ...: no such file or directory
```

**Diagnosis**: Packer's log writer doesn't create the parent directory.

**Fix**: in your wrapper script, `mkdir -p` the parent before invoking Packer:
```bash
PACKER_LOG_PATH="${PACKER_DIR}/output/foo.log"
mkdir -p "$(dirname "$PACKER_LOG_PATH")"
PACKER_LOG=1 PACKER_LOG_PATH="$PACKER_LOG_PATH" packer build ...
```

See memory `feedback_packer_log_dir.md`.

#### VI.7.4 Env vars from `~/.zshrc` don't propagate to non-login shell invocations

**Symptom**: You set `HCP_CLIENT_ID` in `~/.zshrc`, but a subprocess (CI runner, claude-driven bash, etc.) doesn't see it.

**Diagnosis**: `~/.zshrc` only runs for interactive zsh shells. Bash subshells / non-login zsh don't read it.

**Fix**: either move exports to `~/.zshenv` (sources for ALL zsh shells), or extract them on demand:
```bash
eval "$(grep -E '^export (HCP_CLIENT_ID|HCP_CLIENT_SECRET|VAGRANT_CLOUD_ORG)=' ~/.zshrc | sed 's/^export //')"
export HCP_CLIENT_ID HCP_CLIENT_SECRET VAGRANT_CLOUD_ORG
```

#### VI.7.5 `cp: /target: Read-only file system`

**Symptom**: A `cp "$SOURCE" "$STAGE/file"` command tries to write to `/file` (filesystem root).

**Diagnosis**: `$STAGE` was unset (shell session lost) and `${STAGE}/file` expanded to `/file`. The bare-string expansion never errored because no `set -u`.

**Fix**: prefer absolute paths over shell variables for one-shot scripts:
```bash
cp /full/source/path /full/destination/path
```

And/or use `set -u` to catch unset vars early.

#### VI.7.6 Ansible role-vars REPLACE defaults — they don't merge

**Symptom**: You override a complex dict at role-vars level and downstream tasks crash with:
```
'dict object' has no attribute 'sub_key'
```

**Diagnosis**: Ansible's default `hash_behaviour=replace`. Overriding `compliance:` at role-vars drops EVERY unspecified key — defaults don't fill the gaps.

**Fix**: mirror every key the role's tasks reference, OR restructure to flat leaf vars. See `playbooks/packer-bake.yml`'s `compliance:` block for the pattern. Memory: `feedback_ansible_role_vars_replace_defaults.md`.

#### VI.7.7 Cross-distro Ansible package names diverge silently

**Symptom**: An OS-aware task installs `audit` on Debian → fails because Debian's package is `auditd`.

**Diagnosis**: Package names differ between RHEL (`audit`, `libpwquality`) and Debian (`auditd`, `libpam-pwquality`).

**Fix**: use an OS-keyed dict in `vars:`, not chained ternaries:
```yaml
vars:
  _baseline_pkgs:
    RedHat:
      - audit
      - libpwquality
    Debian:
      - auditd
      - libpam-pwquality
loop: "{{ _baseline_pkgs[ansible_os_family] }}"
```

---

## Appendix A — File layout

```
~/Projects/Infrastrutures/devops-tools/packer/
├── .env.example                                  # template — copy to .env if you want local overrides
├── .gitignore                                    # excludes output/, *.box, *.qcow2, keys/, smoke/
├── README.md                                     # top-level orientation
│
├── docs/
│   ├── end-to-end-guide.md                       # THIS FILE
│   ├── BUILD-WORKFLOW.md                         # two-stage internals
│   ├── build-and-publish-runbook.md              # happy-path operational runbook
│   ├── vagrant-cloud-publish.md                  # registry/publish theory
│   └── rebake-bosch-arm64-runbook.md             # runbook for re-baking after a fix lands
│
├── templates/
│   ├── ubuntu2204-arm64-base.pkr.hcl             # Stage 1 — base OS install
│   ├── bosch-ubuntu2204-arm64-hardened.pkr.hcl   # Stage 2 — hardened bake
│   ├── bosch-ubuntu2204-hardened.pkr.hcl         # x86 legacy monolith (unused on arm64)
│   ├── renesas-rhel9-hardened.pkr.hcl            # renesas-tenant legacy monolith
│   └── box-vagrantfile.qemu.rb                   # embedded Vagrantfile shipped inside the .box
│
├── playbooks/
│   └── packer-bake.yml                           # Ansible playbook invoked by Stage 2
│       (3 new post-tasks for 2026-05-20 fixes — see playbooks/packer-bake.yml line ~95)
│
├── variables/
│   ├── common.pkrvars.hcl                        # shared across tenants
│   ├── bosch-arm64.pkrvars.hcl                   # bosch + arm64
│   ├── bosch.pkrvars.hcl                         # bosch + amd64 (legacy)
│   ├── renesas.pkrvars.hcl                       # renesas + amd64 (legacy)
│   └── ubuntu-arm64-base.pkrvars.hcl             # Stage 1 base
│
├── http/
│   ├── meta-data                                 # cloud-init meta-data (empty file)
│   ├── user-data.tmpl                            # SOURCE OF TRUTH for autoinstall
│   └── user-data                                 # GENERATED — gitignored
│
├── keys/                                         # gitignored
│   ├── packer_ed25519                            # bake-time SSH private key
│   └── packer_ed25519.pub                        # bake-time SSH public key
│
├── scripts/
│   ├── build.sh                                  # wrapper around `packer build`
│   ├── publish.sh                                # uploader + releaser for HCP Vagrant Registry
│   └── verify-image.sh                           # sanity check for an artifact
│
├── output/                                       # gitignored
│   ├── base/                                     # Stage 1 outputs
│   │   └── ubuntu2204-arm64/<YYYY-MM-DD>/
│   │       ├── ubuntu2204-arm64-base-<date>.qcow2
│   │       ├── ubuntu2204-arm64-base-latest.qcow2 → symlink
│   │       ├── efivars.fd
│   │       └── manifest.json
│   └── bosch/arm64/qemu/<image-version>/
│       ├── bosch-ubuntu2204-cisl1-arm64-<ver>.box       # ← what we publish
│       ├── bosch-ubuntu2204-cisl1-arm64-<ver>.qcow2     # raw VM disk
│       ├── efivars.fd                                    # post-bake NVRAM
│       └── manifest.json
│
└── smoke/qemu-bosch-arm64/                       # gitignored regression test suite
    ├── Vagrantfile                               # active — swap between releases
    ├── Vagrantfile.stripped                      # canonical post-bake consumer Vagrantfile
    ├── Vagrantfile.with-workarounds              # legacy pre-fix reference
    ├── smoke-manual.sh                           # Tier A — bypass vagrant
    ├── smoke-vagrant.sh                          # Tier B — vagrant integration
    ├── verify-bake-fixes.sh                      # Tier A++ — verify all 3 fixes via empty-NVRAM boot
    ├── probe-ssh-with-build-key.sh               # diagnostic
    ├── probe-authkeys.exp                        # diagnostic
    └── probe-ssh-keys.sh                         # diagnostic
```

---

## Appendix B — Command cheat sheet

### Build
```bash
# Full base + hardened bake (Stage 1 + Stage 2)
ARCH=arm64 ./scripts/build.sh bosch qemu                                  # base + hardened, both providers

# Just Stage 1 (base only)
ARCH=arm64 STAGE=base ./scripts/build.sh bosch qemu

# Just Stage 2 (hardened only)
ARCH=arm64 STAGE=hardened BASE_VERSION=2026-05-05 ./scripts/build.sh bosch qemu 2026-05-20.1

# Iterate Ansible against an existing qcow2 (no re-install)
ARCH=arm64 STAGE=hardened \
  BASE_IMAGE_PATH=output/base/ubuntu2204-arm64/2026-05-05/ubuntu2204-arm64-base-2026-05-05.qcow2 \
  ./scripts/build.sh bosch qemu 2026-05-20.2
```

### Smoke test
```bash
# Tier A — direct QEMU, all 3 fix verification
./smoke/qemu-bosch-arm64/verify-bake-fixes.sh 2026-05-20.1

# Tier A only the manual boot path (no fix-grading)
./smoke/qemu-bosch-arm64/smoke-manual.sh

# Tier B — vagrant integration (use Vagrantfile.stripped)
cp smoke/qemu-bosch-arm64/Vagrantfile.stripped smoke/qemu-bosch-arm64/Vagrantfile
./smoke/qemu-bosch-arm64/smoke-vagrant.sh

# Diagnostic — boot guest + SSH with build-time key
./smoke/qemu-bosch-arm64/probe-ssh-with-build-key.sh
```

### Publish + release
```bash
# Upload, do NOT release
./scripts/publish.sh bosch 2026-05-20.1 --providers qemu

# Upload, release
./scripts/publish.sh bosch 2026-05-20.1 --providers qemu --release

# Dry-run (echo commands, don't execute)
./scripts/publish.sh bosch 2026-05-20.1 --providers qemu --dry-run
```

### Registry inspection
```bash
vagrant cloud box show     nthedao2705/ubuntu2204-cisl1-arm64
vagrant cloud auth whoami  # auth check
```

### Cleanup
```bash
pkill -KILL -f 'qemu-system' 2>/dev/null
vagrant box remove nthedao2705/ubuntu2204-cisl1-arm64 --all --force 2>/dev/null
rm -rf smoke/qemu-bosch-arm64/.vagrant /tmp/vagrant-qemu-serial.log
```

### Git
```bash
git status
git add packer/
git commit -m "release ${NEW_VER}: <reason>"
git tag -a "bosch-arm64-${NEW_VER}" -m "release notes"
git push && git push --tags
```

---

## Appendix C — Environment variable reference

| Var | Used by | Value | Required for |
|---|---|---|---|
| `ARCH` | `build.sh` | `amd64` (default) \| `arm64` | Build |
| `STAGE` | `build.sh` | `base` \| `hardened` \| `all` (default) | Build (arm64 only) |
| `BASE_VERSION` | `build.sh` | e.g. `2026-05-05`. Auto-defaults to today's date if unset. | Build (`STAGE=hardened` only) |
| `BASE_IMAGE_PATH` | `build.sh` | Override path to base qcow2 | Build (override default base location) |
| `BASE_OVA_PATH` | `build.sh` | Override path to base OVA | Build (virtualbox only) |
| `RHEL_USERNAME` / `RHEL_PASSWORD` | `build.sh` | Red Hat subscription-manager creds | Renesas tenant only |
| `HCP_CLIENT_ID` | `publish.sh`, `vagrant cloud` | HCP IAM service principal client id | Publish + release + private-box pull |
| `HCP_CLIENT_SECRET` | `publish.sh`, `vagrant cloud` | HCP IAM service principal secret | Same |
| `VAGRANT_CLOUD_ORG` | `publish.sh` | **Registry slug** (e.g. `nthedao2705`), NOT HCP org slug | Publish |
| `VAGRANT_CLOUD_TOKEN` | `publish.sh` fallback | Legacy `atlasv1.<token>` or single HCP access token | Publish (deprecated path) |
| `BOX_NAME` | `publish.sh` | Override box name (default: `ubuntu2204-cisl1-${ARCH}`) | Publish |
| `RELEASE` | `publish.sh` | `true` to release. Same effect as `--release`. | Publish |
| `DRY_RUN` | `publish.sh` | `true` to echo without executing. Same as `--dry-run`. | Publish |
| `PROVIDERS_FILTER` | `publish.sh` | Comma list — `qemu`, `virtualbox`, or `qemu,virtualbox`. Same as `--providers`. | Publish |
| `PACKER_LOG` | Packer | `1` to enable Packer's debug log | Diagnosing bake issues |
| `PACKER_LOG_PATH` | Packer | Absolute path. **Must `mkdir -p` parent yourself.** | Diagnosing bake issues |

---

## Appendix D — Further reading & memory pointers

### Topic-focused docs in `packer/docs/`
- [`BUILD-WORKFLOW.md`](./BUILD-WORKFLOW.md) — deep dive on two-stage build, variable resolution, SSH key contract
- [`build-and-publish-runbook.md`](./build-and-publish-runbook.md) — original happy-path runbook (some sections superseded by THIS doc)
- [`vagrant-cloud-publish.md`](./vagrant-cloud-publish.md) — registry/publish theory + alternatives
- [`rebake-bosch-arm64-runbook.md`](./rebake-bosch-arm64-runbook.md) — runbook for re-baking after a fix lands (more recent than build-and-publish-runbook)

### Memory notes in `~/.claude/agent-memory/devops-architect/`
- **`feedback_vagrant_qemu_consumer_boot_pitfalls.md`** — the three layered bugs (NVRAM, virtio-net-pci, authorized_keys) with full diagnostic ladder
- **`feedback_packer_vagrant_pp_no_qemu.md`** — why metadata.json provider must be `libvirt`, three-layer provider naming, registry-slot policy
- **`feedback_vagrant_cloud_hcp_auth.md`** — HCP IAM service principal vs legacy atlasv1, registry-slug vs org-slug distinction
- **`feedback_vagrant_cloud_cli_24x_signatures.md`** — `vagrant cloud` 2.4.x signature changes (version/provider show removed, upload arch positional)
- **`feedback_packer_qemu_user_mode_httpip.md`** — `{{ .HTTPIP }}` wrong from QEMU guest's POV (use SLIRP gateway `10.0.2.2`)
- **`feedback_packer_qemu_macos_display.md`** — `headless = false` needs `-display cocoa` override on macOS
- **`feedback_packer_qemu_aarch64_no_default_gfx.md`** — aarch64 virt needs `ramfb` + `virtio-gpu-pci`
- **`feedback_packer_qemuargs_merge.md`** — qemuargs is flag-keyed REPLACE, not merge
- **`feedback_packer_hcl2_provider_token.md`** — `{{.Provider}}` doesn't work in HCL `locals`
- **`feedback_packer_vbox_arm64_keyboard.md`** — virtualbox arm64 keyboard scancodes
- **`feedback_packer_vagrant_pp_no_qemu.md`** — Packer's stock `vagrant` PP doesn't emit qemu boxes; use shell-local
- **`feedback_packer_validate_runs_all_sources.md`** — `packer validate` runs against all sources regardless of `-only`
- **`feedback_bash_strict_empty_array.md`** — Apple bash 3.2 + `set -u` + empty array trap
- **`feedback_ansible_yaml_callback_removed.md`** — `stdout_callback = yaml` removed in community.general 12.0.0
- **`feedback_ansible_cross_distro_packages.md`** — RHEL `audit` vs Debian `auditd` etc.
- **`feedback_ansible_role_vars_replace_defaults.md`** — role-vars replace, not merge
- **`feedback_packer_log_dir.md`** — `PACKER_LOG_PATH` parent must be created manually
- **`feedback_icloud_dev_workflow.md`** — keep dev repos out of `~/Documents` / `~/Desktop`
- **`feedback_research_after_three_fails.md`** — after 3 failed fixes, stop guessing and research
- **`feedback_research_official_sources_first.md`** — fetch official pages before searching forums
- **`reference_chef_bento_authoritative_vagrant.md`** — chef/bento as authoritative reference for multi-arch Vagrant boxes

### External authoritative references
- **vagrant-qemu plugin**: https://github.com/ppggff/vagrant-qemu
- **vagrant-libvirt example box format**: https://github.com/vagrant-libvirt/vagrant-libvirt/blob/main/example_box/
- **Ubuntu autoinstall reference**: https://canonical-subiquity.readthedocs-hosted.com/en/latest/reference/autoinstall-reference.html
- **HCP Vagrant migration guide**: https://developer.hashicorp.com/vagrant/vagrant-cloud/hcp-vagrant/post-migration-guide
- **HCP IAM service principals**: https://developer.hashicorp.com/hcp/docs/hcp/iam/service-principal
- **CIS Ubuntu 22.04 Benchmark v2.0**: https://www.cisecurity.org/benchmark/ubuntu_linux
- **chef/bento (Vagrant box reference repo)**: https://github.com/chef/bento

---

**Document maintainer**: this file should be updated alongside any change to:
- `playbooks/packer-bake.yml` (especially post-tasks)
- `templates/bosch-ubuntu2204-arm64-hardened.pkr.hcl` (shell-local PP)
- `templates/box-vagrantfile.qemu.rb` (embedded Vagrantfile)
- `scripts/publish.sh` (provider expansion, release flow)
- `scripts/build.sh` (env-var contract)
- The smoke harness scripts

Last revised: **2026-05-20** after the `bosch-arm64-2026-05-20.1` release cycle.
