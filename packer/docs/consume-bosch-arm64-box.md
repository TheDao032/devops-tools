# Consumer guide — running the bosch arm64 Vagrant box

End-to-end procedure for a **brand-new Apple Silicon Mac** to bootstrap, fetch,
boot, and SSH into the published `nthedao2705/ubuntu2204-cisl1-arm64` box.

**Target audience**: an engineer who's never touched this project before and
needs a CIS-L1-hardened Ubuntu 22.04 ARM64 VM running locally for development
or testing.

**Time to first SSH**: ~10 min on a fresh Mac, ~2 min on a Mac with deps
already installed.

---

## Table of contents

- [Prerequisites](#prerequisites)
- [Phase 1 — Install tooling (one-time, ~5 min)](#phase-1--install-tooling-one-time-5-min)
- [Phase 2 — Configure HCP authentication (one-time, ~3 min)](#phase-2--configure-hcp-authentication-one-time-3-min)
- [Phase 3 — Create a workspace + Vagrantfile (~30 sec)](#phase-3--create-a-workspace--vagrantfile-30-sec)
- [Phase 4 — Boot the VM (~2 min)](#phase-4--boot-the-vm-2-min)
- [Phase 5 — SSH in + do work](#phase-5--ssh-in--do-work)
- [Phase 6 — Lifecycle commands (start, stop, destroy, rebuild)](#phase-6--lifecycle-commands-start-stop-destroy-rebuild)
- [Vagrantfile reference](#vagrantfile-reference)
- [Troubleshooting](#troubleshooting)
- [Appendix — what each line of the Vagrantfile does](#appendix--what-each-line-of-the-vagrantfile-does)

---

## Prerequisites

| Requirement | Why |
|---|---|
| Apple Silicon Mac (M1/M2/M3/M4) | QEMU + HVF accelerator only works on ARM64 Macs for ARM64 VMs |
| macOS 13+ (Ventura or newer) | Hypervisor.framework features used by QEMU 11.x |
| ≥ 8 GB free disk (10 GB recommended) | The .box file is ~1.4 GB; VM disk grows to ~4 GB |
| ≥ 4 GB available RAM | VM defaults to 2 GB; you'll want headroom |
| HCP Vagrant Registry **read** access | The box is private — your HCP account must have access to `nthedao2705/ubuntu2204-cisl1-arm64` |
| HCP IAM service principal credentials (client ID + secret) | Required to authenticate `vagrant cloud` and `vagrant up` for private boxes |

> ⚠️ Don't put this workspace in `~/Documents` or `~/Desktop` — iCloud Drive's
> "Optimize Mac Storage" can silently evict files mid-`vagrant up` and break
> the VM. Canonical location: `~/vagrant-vms/` or `~/Projects/`.

---

## Phase 1 — Install tooling (one-time, ~5 min)

Skip any of these if already installed.

### 1.1 Install Homebrew (if missing)

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

Then in a fresh shell verify: `brew --version`.

### 1.2 Install QEMU + Vagrant + jq

```bash
brew install qemu                # 8.0+ required (we run 11.0+)
brew install --cask vagrant      # 2.4.3+ required for HCP env-var auth
brew install jq                  # Used by troubleshooting commands below
```

Verify:
```bash
qemu-system-aarch64 --version | head -1   # expect: 8.x or 11.x
vagrant --version                          # expect: Vagrant 2.4.3+
```

> ⚠️ Vagrant **must be 2.4.3 or newer**. Earlier versions don't read
> `HCP_CLIENT_ID` / `HCP_CLIENT_SECRET` env vars automatically and break
> private-box pulls.

### 1.3 Install the vagrant-qemu plugin

```bash
vagrant plugin install vagrant-qemu
```

Verify:
```bash
vagrant plugin list | grep vagrant-qemu     # expect: vagrant-qemu (0.3.x+)
```

---

## Phase 2 — Configure HCP authentication (one-time, ~3 min)

The box is private — anonymous `vagrant up` will get 404. You need an HCP
IAM service principal.

### 2.1 Create a service principal (if you don't have one)

If your organization has already issued you a service principal, skip to 2.2.

1. Go to https://portal.cloud.hashicorp.com/
2. Pick your organization → **Access control (IAM)** → **Service principals** → **Create service principal**
3. Name it (e.g., `vagrant-consumer-<your-laptop-name>`), assign role **Contributor** at the org level
4. Click into the new SP → **Service principal keys** → **Generate new key**
5. **Save `client_id` + `client_secret` immediately** — the secret is shown only once
6. Save both in a password manager (e.g., Bitwarden, 1Password)

### 2.2 Export the env vars

Add to `~/.zshrc` (or wherever you put shell env vars):
```bash
export HCP_CLIENT_ID="<from step 2.1>"
export HCP_CLIENT_SECRET="<from step 2.1>"
export VAGRANT_CLOUD_ORG="nthedao2705"   # REGISTRY slug, NOT the HCP org slug
```

> ⚠️ `VAGRANT_CLOUD_ORG` must be `nthedao2705` (the legacy Vagrant Cloud
> username = registry slug), **NOT** the HCP org slug (`nthedao2705-org`).
> Setting it to the HCP org slug produces
> `Vagrant Cloud request failed - registry not found`.

Reload:
```bash
source ~/.zshrc
```

Verify:
```bash
echo "HCP_CLIENT_ID:     ${HCP_CLIENT_ID:+set (len=${#HCP_CLIENT_ID})}"
echo "HCP_CLIENT_SECRET: ${HCP_CLIENT_SECRET:+set (len=${#HCP_CLIENT_SECRET})}"
echo "VAGRANT_CLOUD_ORG: ${VAGRANT_CLOUD_ORG}"
```

All three must be set.

### 2.3 Smoke-test auth

```bash
vagrant cloud box show nthedao2705/ubuntu2204-cisl1-arm64
```

Expected output:
```
Box:             nthedao2705/ubuntu2204-cisl1-arm64
Private:         yes
Current Version: 2026-05-20.1   (or newer)
Versions:        2026-05-05.1, 2026-05-20.1, ...
```

If you get `Failed to locate requested box` → auth is broken. Check:
- Env vars actually exported (`echo $HCP_CLIENT_ID`)
- VAGRANT_CLOUD_ORG = `nthedao2705` (not `nthedao2705-org`)
- Your HCP account has read access to this box

---

## Phase 3 — Create a workspace + Vagrantfile (~30 sec)

### 3.1 Create a workspace directory

```bash
mkdir -p ~/vagrant-vms/bosch-ubuntu && cd ~/vagrant-vms/bosch-ubuntu
```

Each VM lives in its own directory — `.vagrant/` state goes here.

### 3.2 Create the Vagrantfile

Use this **tested** Vagrantfile (every line incorporates a fix from the
2026-05 release cycle — see [Appendix](#appendix--what-each-line-of-the-vagrantfile-does)
for explanations):

```ruby
Vagrant.configure("2") do |config|
  # The published box. Anyone with HCP read access can pull this.
  config.vm.box              = "nthedao2705/ubuntu2204-cisl1-arm64"
  config.vm.box_architecture = "arm64"

  # macOS's SMB synced-folder integration requires "Windows File Sharing"
  # which Apple removed from the default System Settings UI. Disable to
  # avoid the username/password prompt during `vagrant up`.
  config.vm.synced_folder ".", "/vagrant", disabled: true

  # CIS-L1-hardened images can take 90-180s on first boot (cloud-init re-runs,
  # audit daemon initialization). Default 300s sometimes isn't enough.
  config.vm.boot_timeout = 600

  # The box's embedded Vagrantfile already sets sensible qemu defaults
  # (virtio-net-pci NIC, ssh_port 50022, cpu=host, memory=2048MB, smp=2).
  # If you want to override, add a config.vm.provider :qemu block here.
  # Example: bump RAM to 4GB:
  #
  # config.vm.provider :qemu do |qe|
  #   qe.memory = "4096"
  # end
end
```

Save as `Vagrantfile` (no extension) in your workspace dir.

---

## Phase 4 — Boot the VM (~2 min)

### 4.1 First boot (includes download)

```bash
vagrant up --provider qemu
```

What happens:
1. Vagrant queries the HCP Vagrant Registry for the latest released version
2. Downloads the `.box` file (~1.4 GB) — takes 1-3 min depending on bandwidth
3. Caches it at `~/.vagrant.d/boxes/nthedao2705-VAGRANTSLASH-ubuntu2204-cisl1-arm64/`
4. Creates a per-VM directory at `.vagrant/machines/default/qemu/vq_<id>/`
5. Launches QEMU with the qcow2 + UEFI firmware
6. Waits for SSH to come up on port 50022 (the box's default)
7. Auto-rotates the Vagrant insecure SSH key for security

Expected milestone output:
```
==> default: Box 'nthedao2705/ubuntu2204-cisl1-arm64' could not be found.
    Attempting to find and install...
    default: Box Provider: libvirt
==> default: Adding box 'nthedao2705/ubuntu2204-cisl1-arm64' (v2026-05-20.1) for provider: libvirt (arm64)
    default: Downloading: https://vagrantcloud.com/.../providers/libvirt/arm64/vagrant.box
[progress bar...]
==> default: Importing a QEMU instance
==> default: Starting the instance...
==> default: Waiting for machine to boot. This may take a few minutes...
    default: SSH address: 127.0.0.1:50022
    default: SSH username: packer
    default: SSH auth method: private key
    default: Vagrant insecure key detected. Vagrant will automatically replace
    default: this with a newly generated keypair for better security.
    default: Inserting generated public key within guest...
    default: Key inserted! Disconnecting and reconnecting using new SSH key...
==> default: Machine booted and ready!
```

🚦 **Success criterion**: `Machine booted and ready!` appears.

> ℹ️ "Box Provider: libvirt" looks confusing but is correct. The
> vagrant-qemu plugin reuses vagrant-libvirt's box format internally;
> see [Troubleshooting](#troubleshooting) "Why does it say libvirt?".

---

## Phase 5 — SSH in + do work

```bash
vagrant ssh
```

Inside the VM:
```
Authorized access only — BOSCH

This system is for the use of authorized users only. ...

packer@ubuntu-builder:~$
```

You're now inside a hardened Ubuntu 22.04 ARM64 VM.

### What's in the box

```bash
# Verify image metadata
cat /etc/image-metadata
# Should show:
# tenant=bosch
# compliance_profile=cis-l1
# image_version=2026-05-20.1
# os_distribution=Ubuntu
# os_version=22.04

# Verify CIS-L1 hardening (some examples)
sudo sshd -T | grep -iE 'permitroot|password'     # PermitRootLogin no; PasswordAuthentication no
sudo ufw status 2>/dev/null                       # inactive (it's there but not enabled by default)
sudo aa-status | head -3                          # apparmor active, ~40 profiles loaded
sudo cat /etc/security/pwquality.conf | head -3   # minlen 12, etc.

# Network
ip -brief addr                                    # enp0s1 should show 10.0.2.15/24
```

### Exit the VM (but keep it running)

```bash
exit
# Or Ctrl-D
```

---

## Phase 6 — Lifecycle commands (start, stop, destroy, rebuild)

All run from your workspace dir (where the Vagrantfile lives).

### Suspend / resume (fastest restart)

```bash
vagrant suspend    # saves VM state to disk; ~10 sec
vagrant resume     # restores; ~5 sec
```

### Halt / up (clean shutdown / restart)

```bash
vagrant halt       # graceful shutdown via SSH; ~30 sec
vagrant up         # boots from saved state; ~30 sec
```

### Destroy (wipe VM, keep cached box)

```bash
vagrant destroy -f
# Next `vagrant up` re-creates the VM from the cached .box (no re-download).
```

### Force-refresh the box (pull newer version if released)

```bash
vagrant box update --provider qemu
# Then:
vagrant destroy -f
vagrant up --provider qemu
```

### Nuke everything (cached box + VM state)

```bash
vagrant destroy -f
vagrant box remove nthedao2705/ubuntu2204-cisl1-arm64 --all --force
rm -rf .vagrant
# Next `vagrant up --provider qemu` re-downloads from scratch.
```

---

## Vagrantfile reference

For copy-paste convenience, the canonical Vagrantfile:

```ruby
Vagrant.configure("2") do |config|
  config.vm.box              = "nthedao2705/ubuntu2204-cisl1-arm64"
  config.vm.box_architecture = "arm64"
  config.vm.synced_folder ".", "/vagrant", disabled: true
  config.vm.boot_timeout     = 600
end
```

That's the minimum needed. Everything else (provider settings, networking,
SSH port, user) comes from the embedded Vagrantfile inside the box.

### Customized version — extra resources, port forward, NFS sync

If your work needs more CPU/RAM or you want to access guest services from
the host:

```ruby
Vagrant.configure("2") do |config|
  config.vm.box              = "nthedao2705/ubuntu2204-cisl1-arm64"
  config.vm.box_architecture = "arm64"

  # NFS-based sync (host requires `sudo` once to update /etc/exports)
  config.vm.synced_folder ".", "/vagrant", type: "nfs", nfs_udp: false

  config.vm.boot_timeout = 600

  # Forward a guest port to host (e.g., for a web server)
  config.vm.network "forwarded_port", guest: 8080, host: 8080, host_ip: "127.0.0.1"

  # Bump resources
  config.vm.provider :qemu do |qe|
    qe.memory = "4096"           # MB
    qe.smp    = "cpus=4,sockets=1,cores=4,threads=1"
  end
end
```

> ⚠️ vagrant-qemu 0.3.x has limited support for `config.vm.network` —
> port-forwarding works but other network types (bridged, private_network)
> may warn or fail. NFS sync works on macOS but requires Vagrant to be
> able to `sudo` (you'll be prompted on first `up`).

---

## Troubleshooting

### "Box could not be found" / 404

**Symptom**:
```
The box 'nthedao2705/ubuntu2204-cisl1-arm64' could not be found...
URL: https://vagrantcloud.com/.../ubuntu2204-cisl1-arm64
Error: The requested URL returned error: 404
```

**Causes + fixes**:

| Cause | Fix |
|---|---|
| Env vars not exported | `echo $HCP_CLIENT_ID` should show 32 chars; if empty, re-source shell init |
| `VAGRANT_CLOUD_ORG` = `nthedao2705-org` (HCP org slug) | Set to `nthedao2705` (registry slug) |
| HCP service principal lacks read access | Contact admin to grant Contributor role |
| Box was unreleased / deprecated | Run `vagrant cloud box show ...` to see `Current Version` |

### "The box you're attempting to add doesn't support the provider you requested"

**Symptom**:
```
==> default: Box Provider: libvirt
The box you're attempting to add doesn't support the provider you requested.
Requested provider: libvirt
```

**Cause**: The box was uploaded to the registry only under `provider=qemu`,
but the vagrant-qemu plugin internally queries `provider=libvirt`. This
shouldn't happen with the current box — it's published under both slots.

**Fix**: Verify both slots exist:
```bash
vagrant cloud box show nthedao2705/ubuntu2204-cisl1-arm64
# Should list at least 2 providers per version (qemu AND libvirt)
```

If `libvirt` is missing, ping the box maintainer to upload it.

### Boot hangs at UEFI / "Image at … start failed"

**Symptom** (serial log shows):
```
ArmTrngLib could not be correctly initialized.
Error: Image at 000BFDB6000 start failed: 00000001
Tpm2SubmitCommand - Tcg2 - Not Found
[no further output]
```

**Cause**: This was a known bug in versions before `2026-05-20.1` — the
box was missing `/EFI/BOOT/BOOTAA64.EFI` (UEFI removable-media fallback).
Fixed in 2026-05-20.1 onward.

**Fix**:
```bash
vagrant box remove nthedao2705/ubuntu2204-cisl1-arm64 --all --force
vagrant up --provider qemu    # re-pulls latest version (2026-05-20.1+)
```

### Boot succeeds but `vagrant up` times out at "Waiting for machine to boot"

**Symptom**: VM is running but Vagrant gives up after `boot_timeout`.

**Causes + fixes**:

| Cause | Fix |
|---|---|
| First-boot took longer than 300s (default) | Already mitigated by `boot_timeout = 600` in our Vagrantfile |
| Guest NIC not coming up (was `eth0`, broke netplan) | Bug in box versions before 2026-05-20.1 — re-pull |
| sshd not in `authorized_keys` (Subiquity dropped 2nd entry) | Bug in box versions before 2026-05-20.1 — re-pull |

If you're on the latest box and still timing out:
```bash
# Check if QEMU process is alive
ps -ef | grep qemu-system-aarch64 | grep -v grep

# Try connecting manually
nc -zv 127.0.0.1 50022
ssh -i ~/.vagrant.d/insecure_private_keys/vagrant.key.rsa \
    -p 50022 -o StrictHostKeyChecking=no packer@127.0.0.1
```

### `vagrant up` prompts for SMB username/password

**Symptom**:
```
==> default: Preparing SMB shared folders...
    default: Username (user[@domain]):
```

**Cause**: `vagrant-qemu`'s default synced-folder type is SMB on macOS;
macOS removed legacy "Windows File Sharing" from default System Settings.

**Fix**: Disable the synced folder (our Vagrantfile already does this):
```ruby
config.vm.synced_folder ".", "/vagrant", disabled: true
```

### "Vagrant cannot forward the specified ports … port 50022 is already in use"

**Symptom**: Second `vagrant up` after a timeout fails with port collision.

**Cause**: Previous `vagrant destroy` didn't reap the QEMU process. Common
when boot timed out.

**Fix**:
```bash
pkill -KILL -f 'qemu-system-aarch64'
sleep 2
lsof -nP -iTCP:50022 -sTCP:LISTEN    # confirm empty
vagrant up --provider qemu
```

Or add this helper to `~/.zshrc.local`:
```bash
vagrant_qemu_nuke() {
  pkill -INT  -f 'qemu-system-aarch64' 2>/dev/null
  sleep 2
  pkill -KILL -f 'qemu-system-aarch64' 2>/dev/null
  rm -rf .vagrant
  echo "qemu killed + .vagrant cleared"
}
```

### Why does it say `libvirt`?

**Symptom**: `vagrant up` says "Box Provider: libvirt" even though you
passed `--provider qemu`.

**Cause**: The vagrant-qemu plugin reuses vagrant-libvirt's box format
(qcow2 + metadata.json). Internally it queries the registry for a
`libvirt`-tagged box. The box is uploaded to BOTH `qemu` and `libvirt`
slots — what you're seeing is the plugin's internal name, not yours.

**Not a problem** — just confusing the first time. Documented in
[`packer/docs/end-to-end-guide.md`](./end-to-end-guide.md) §IV.4
("Three-layer provider naming").

### Need to inspect the box's embedded Vagrantfile?

```bash
# Find the cached box dir
BOX_DIR="$HOME/.vagrant.d/boxes/nthedao2705-VAGRANTSLASH-ubuntu2204-cisl1-arm64"
LATEST=$(ls -1 "$BOX_DIR" | sort -V | tail -1)
cat "$BOX_DIR/$LATEST/arm64/libvirt/Vagrantfile"
```

This shows the qemu provider defaults the box ships with.

---

## Appendix — what each line of the Vagrantfile does

```ruby
# Line 1: the registry box ID
config.vm.box = "nthedao2705/ubuntu2204-cisl1-arm64"
# `nthedao2705` is the registry slug; `ubuntu2204-cisl1-arm64` is the box name.
# Anyone with HCP read access to this private box can pull it.

# Line 2: required for multi-arch boxes
config.vm.box_architecture = "arm64"
# Without this, Vagrant 2.4.x may try to resolve x86_64 metadata.
# The box is published with `--architecture arm64` so this MUST match.

# Line 3: disable SMB synced folder
config.vm.synced_folder ".", "/vagrant", disabled: true
# Default = SMB on macOS; macOS removed "Windows File Sharing" config UI
# in recent versions, so SMB auth prompts hang.
# Alternatives: type: "rsync" (one-way) or type: "nfs" (needs sudo).

# Line 4: extend boot timeout
config.vm.boot_timeout = 600
# CIS-L1 boxes first-boot can take 90-180s (cloud-init, audit daemon,
# AppArmor profile load). Default 300s is enough for warm boots but
# tight for first boots. 600s is belt-and-braces.
```

What's NOT in the file (but defaulted by the box):

| Setting | Default | Where it comes from |
|---|---|---|
| `qe.arch` | `aarch64` | Embedded Vagrantfile in the box |
| `qe.machine` | `virt,accel=hvf,highmem=on` | Embedded |
| `qe.cpu` | `host` | Embedded |
| `qe.smp` | `cpus=2,sockets=1,cores=2,threads=1` | Embedded |
| `qe.memory` | `2048` (MB) | Embedded |
| `qe.net_device` | `virtio-net-pci` | Embedded (critical for netplan match) |
| `qe.ssh_port` | `50022` | Embedded |
| `config.ssh.username` | `packer` | Embedded |
| EFI firmware | `/opt/homebrew/share/qemu/edk2-aarch64-code.fd` | vagrant-qemu plugin default |

You can override any of these in YOUR Vagrantfile by adding a
`config.vm.provider :qemu do |qe| ... end` block.

---

## Related docs

- [`end-to-end-guide.md`](./end-to-end-guide.md) — full lifecycle from baking to publishing
- [`rebake-bosch-arm64-runbook.md`](./rebake-bosch-arm64-runbook.md) — runbook for re-baking after a fix
- [`build-and-publish-runbook.md`](./build-and-publish-runbook.md) — happy-path operational runbook
- chezmoi user's `~/.config/dotfiles/docs/CHEZMOI-CONCEPTS.md` — if you're using chezmoi to manage your `~/.zshrc`, the HCP env vars belong in the encrypted secrets file

---

**Document maintainer**: update this doc whenever you bump a tooling
version requirement, add a new troubleshooting case, or change the
canonical Vagrantfile template.

Last revised: 2026-05-25 — initial consumer guide post-2026-05-20.1 release.
