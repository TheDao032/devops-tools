# Packer build workflow — two-stage hardened image baking

> **Scope:** this doc covers the **arm64 + bosch** path which uses the
> two-stage build. The amd64 (bosch + renesas) path still uses the legacy
> monolith template — see `README.md` for that. Migration to two-stage for
> amd64 is parked behind "first prove the pattern on arm64."

---

## Table of contents

1. [Why two stages](#why-two-stages)
2. [The 30-second mental model](#the-30-second-mental-model)
3. [Architecture diagram](#architecture-diagram)
4. [Files that participate](#files-that-participate)
5. [Stage 1 — bake the base](#stage-1--bake-the-base-os-only-no-ansible)
6. [Stage 2 — apply hardening](#stage-2--apply-hardening-ansible-only-no-os-install)
7. [The `build.sh` wrapper, end-to-end](#the-buildsh-wrapper-end-to-end)
8. [Common workflows](#common-workflows)
9. [The SSH key contract](#the-ssh-key-contract)
10. [The `cloud-init` user-data contract](#the-cloud-init-user-data-contract)
11. [Variable resolution and precedence](#variable-resolution-and-precedence)
12. [Output directory layout](#output-directory-layout)
13. [Failure modes per stage](#failure-modes-per-stage)
14. [What's parked for later](#whats-parked-for-later)

---

## Why two stages

The monolith template (`bosch-ubuntu2204-arm64-hardened.pkr.hcl` pre-split)
did everything in one packer run: OS install AND ansible compliance. That has
two costs that get paid every time anything fails:

1. **Iteration cost.** A typo in the ansible role meant re-running the full
   12-15 min OS install before you could see the next ansible error.
2. **Failure entanglement.** A boot timing bug and a compliance role bug
   look identical from the outside ("packer build failed at step X").

Two-stage separates the two:

| | Stage 1 (base) | Stage 2 (hardened) |
|---|---|---|
| What | OS install via cloud-init | Compliance role via ansible |
| Time | ~12-15 min | ~3 min |
| Output | `output/base/.../*.qcow2` | `output/bosch/.../*.qcow2` |
| Refresh cadence | Quarterly / on CVE | Every commit / every iteration |
| When it fails | OS install / autoinstall / boot | Ansible role logic |

The base is **tenant-agnostic** — same Ubuntu base feeds bosch, future
customer-X, future internal-test, etc. Each tenant variant only re-pays the
~3 min hardening cost.

---

## The 30-second mental model

```
ISO ──install──▶ base.qcow2 ──ansible──▶ bosch-hardened.qcow2
       (12 min)               (3 min)
       STAGE=base              STAGE=hardened
       monthly-ish             every iteration
```

Stage 1 produces a clean, authenticatable Ubuntu disk. Stage 2 boots that
disk and applies tenant policy.

---

## Architecture diagram

```
                ┌────────────────────────────────────────────────┐
                │  Apple Silicon Mac (the bake host)             │
                │                                                │
   Ubuntu       │   ┌────────────┐   ┌────────────┐              │
   22.04 ARM64  │   │ qemu+hvf   │   │ ansible-   │              │
   live ISO ────┼─▶ │ (stage 1)  │   │ playbook   │              │
                │   │            │   │ (stage 2)  │              │
                │   └─────┬──────┘   └──────▲─────┘              │
                │         │                 │                    │
                │         ▼                 │                    │
                │    base qcow2 ────────────┘                    │
                │    (~3.8 GB)                                   │
                │         │                                      │
                │         ▼                                      │
                │  bosch-hardened qcow2                          │
                │  (~3.8 GB, identical layout, hardened content) │
                └────────────────────────────────────────────────┘
                                                    │
                                                    ▼
                                       deployed via Vagrant /
                                       Proxmox / VMware Fusion
                                       on ARM64 hosts only
```

The two stages share three contracts:
- **The SSH keypair** under `keys/packer_ed25519` (stage 1 injects pub via
  cloud-init; stage 2 SSHes in with priv)
- **The `packer` user** that cloud-init creates (stage 2 ansible runs as it)
- **Disk format & layout** — both stages run qemu+hvf, virtio interfaces,
  EFI boot, so the qcow2 produced by stage 1 boots cleanly under stage 2's
  qemu source

---

## Files that participate

```
packer/
├── http/
│   ├── user-data.tmpl        ← STAGE 1 ONLY. Cloud-init seed template
│   │                            (committed; @@SSH_PUBKEY@@ placeholder)
│   ├── user-data             ← STAGE 1 ONLY. Rendered by build.sh on every
│   │                            run from .tmpl + keys/packer_ed25519.pub
│   │                            (gitignored)
│   └── meta-data             ← Cloud-init's nocloud "meta-data" (empty file)
│
├── keys/                     ← (gitignored). SSH keypair for both stages
│   ├── packer_ed25519        ← Private. Both stages' qemu source uses this
│   │                            for SSH and the ansible provisioner
│   └── packer_ed25519.pub    ← Public. Substituted into user-data by build.sh
│
├── playbooks/
│   ├── ansible.cfg           ← STAGE 2. Callback plugin, retry settings
│   ├── inventory.ini         ← Unused in two-stage (packer auto-generates
│   │                            inventory_file_template at runtime)
│   └── packer-bake.yml       ← STAGE 2. Wrapper play that imports the
│                                compliance role with tenant-specific vars
│
├── templates/
│   ├── ubuntu2204-arm64-base.pkr.hcl              ← STAGE 1
│   ├── bosch-ubuntu2204-arm64-hardened.pkr.hcl    ← STAGE 2
│   ├── bosch-ubuntu2204-hardened.pkr.hcl          ← x86 monolith (legacy)
│   └── renesas-rhel9-hardened.pkr.hcl             ← x86 monolith (legacy)
│
├── variables/
│   ├── common.pkrvars.hcl              ← Both stages
│   ├── ubuntu-arm64-base.pkrvars.hcl   ← STAGE 1 only
│   ├── bosch-arm64.pkrvars.hcl         ← STAGE 2 only
│   ├── bosch.pkrvars.hcl               ← x86 monolith
│   └── renesas.pkrvars.hcl             ← x86 monolith
│
├── scripts/
│   └── build.sh                       ← Orchestrator for both stages
│
└── output/                             ← (gitignored)
    ├── base/                          ← STAGE 1 outputs
    │   └── ubuntu2204-arm64/
    │       └── <BASE_VERSION>/
    │           ├── ubuntu2204-arm64-base-<BASE_VERSION>.qcow2
    │           └── manifest.json
    └── bosch/arm64/qemu/              ← STAGE 2 outputs
        └── <IMAGE_VERSION>/
            ├── bosch-ubuntu2204-cisl1-arm64-<IMAGE_VERSION>.qcow2
            └── manifest.json
```

External files referenced (outside `packer/`):

```
ansible/playbooks/roles/compliance/    ← role applied by stage 2
                                          (shared with deploy-time playbooks)
~/iso-cache/ubuntu-22.04.5-live-server-arm64.iso
                                       ← ISO consumed by stage 1
                                          (canonical home: cdimage.ubuntu.com)
```

---

## Stage 1 — bake the base (OS-only, no ansible)

### Trigger

```bash
ARCH=arm64 STAGE=base ./scripts/build.sh bosch qemu
```

(`STAGE=base` forces stage 1 only; without `STAGE=`, the wrapper runs both.)

### Step-by-step

1. **`build.sh` resolves variables.**
   - Reads `ARCH=arm64`, `STAGE=base`, `BASE_VERSION=$(date +%F)` (default,
     overridable).
   - Picks template `templates/ubuntu2204-arm64-base.pkr.hcl` and var-file
     `variables/ubuntu-arm64-base.pkrvars.hcl`.

2. **`build.sh` ensures the SSH keypair exists** under `keys/packer_ed25519`.
   - First run: generates ed25519 keypair, no passphrase.
   - Subsequent runs: reuses existing keypair.

3. **`build.sh` renders `http/user-data`** from `http/user-data.tmpl` by
   substituting `@@SSH_PUBKEY@@` → the contents of `keys/packer_ed25519.pub`.
   This rendered file is what packer serves to cloud-init.

4. **`packer init` + `packer validate`** are run against stage 1's template
   (downloads plugins if needed; validates HCL).

5. **`packer build` starts.** It launches `qemu-system-aarch64`:
   - Apple `hvf` accelerator (native ARM64, no emulation)
   - EFI boot via pflash (firmware code = EDK2 read-only, vars = mutable
     per-VM copy of NVRAM)
   - 4 vCPU, 4 GB RAM, 20 GB disk (from `common.pkrvars.hcl`)
   - Mounts the Ubuntu live-server ISO as install media
   - Mounts no second disk — the qcow2 is created fresh
   - Starts a tiny HTTP server on `http_directory` (= `http/`) to serve
     `user-data` and `meta-data` to cloud-init
   - Starts a tiny VNC server on `127.0.0.1:5900` (used to inject the boot
     command)

6. **Packer waits 10 sec** (`boot_wait`), then types the boot command into
   the EDK2/GRUB menu via VNC keystrokes:
   - `e` to edit the default boot entry
   - 3× `<down>` to land on the `linux` line (NOT 2 — see template comments)
   - `<end>` to jump to end-of-line
   - Append ` autoinstall ds="nocloud;s=http://10.0.2.2:<port>/"` (10.0.2.2
     is the SLIRP gateway; `<port>` is packer's per-build HTTP port)
   - `Ctrl-X` to boot

7. **The kernel boots, finds the autoinstall datasource over HTTP, fetches
   `user-data`.** Subiquity (Ubuntu's installer) reads it and provisions:
   - Hostname: `ubuntu-builder`
   - User: `packer` with sha512 password "packer" + the public SSH key
   - LVM whole-disk layout
   - DHCP networking
   - Packages: `openssh-server`, `python3`, `python3-apt`, `sudo`
   - Sudoers: `packer ALL=(ALL) NOPASSWD:ALL`

8. **Reboot.** Subiquity reboots into the installed system.

9. **Packer waits for SSH** (`ssh_timeout = 45m`, set in
   `common.pkrvars.hcl`). Connects as `packer` using the bake-time SSH key.

10. **The single shell provisioner runs** — writes `/etc/base-image-metadata`
    so stage 2 images can prove their base lineage. (No ansible.)

11. **Packer issues `shutdown_command`** (`sudo /sbin/shutdown -hP now`) to
    cleanly power off the VM.

12. **Packer copies the qcow2** from qemu's working dir into
    `output/base/ubuntu2204-arm64/<BASE_VERSION>/ubuntu2204-arm64-base-<BASE_VERSION>.qcow2`
    and writes `manifest.json` next to it.

13. **`build.sh` updates the `latest/` symlink** so stage 2's default
    `base_image_path` resolves:
    ```
    output/base/ubuntu2204-arm64/latest → ../<BASE_VERSION>
    ```

### What you should see in the log

- `==> packer init / validate / build` headers
- A long stretch of cloud-init noise as Subiquity installs (~10 min)
- `==> Waiting for SSH to become available...`
- `==> Provisioning with shell script` (the metadata stamper)
- `==> Gracefully halting virtual machine`
- `Builds finished. The artifacts of successful builds are: ...`

---

## Stage 2 — apply hardening (ansible-only, no OS install)

### Trigger

```bash
# Default — uses the latest base
ARCH=arm64 STAGE=hardened ./scripts/build.sh bosch qemu

# Explicit base override (e.g. iterate against a known qcow2)
ARCH=arm64 STAGE=hardened \
  BASE_IMAGE_PATH=output/bosch/arm64/qemu/2026-05-03.1/bosch-ubuntu2204-cisl1-arm64-2026-05-03.1.qcow2 \
  ./scripts/build.sh bosch qemu
```

### Step-by-step

1. **`build.sh` resolves the base image.**
   - If `BASE_IMAGE_PATH=` is set, uses it verbatim.
   - Otherwise, defaults to
     `output/base/ubuntu2204-arm64/<BASE_VERSION>/ubuntu2204-arm64-base-<BASE_VERSION>.qcow2`
   - **Refuses to proceed** if no base qcow2 exists at the resolved path —
     prints a clear error pointing you at `STAGE=base`.

2. **`build.sh` re-renders `http/user-data`** (as in stage 1).
   - Stage 2 doesn't actually serve `http/user-data` — but the wrapper does
     this unconditionally because it's cheap and keeps the rendered file
     in sync with the current keypair. Idempotent.

3. **`packer init` + `packer validate`** are run against stage 2's template
   with `-var base_image_path=<resolved>`.

4. **`packer build` starts.** It launches `qemu-system-aarch64`:
   - Same `hvf` + EFI + qemuargs as stage 1 (must match — the disk was
     installed under these conditions)
   - **Loads the base qcow2 as the boot disk** via `disk_image = true`
     (this is the key flag: it tells packer "iso_url is a bootable disk,
     not an installer ISO")
   - **No `boot_command`, no `http_directory`, no `boot_wait`** — packer
     just boots and waits for SSH

5. **The base boots normally** — same kernel, same systemd, same `packer`
   user, same authorized_keys (because all of that is on the disk from
   stage 1).

6. **Packer waits for SSH** and connects with the same `keys/packer_ed25519`
   private key.

7. **The shell provisioner runs** — `apt-get install python3 python3-apt
   aptitude` (defensive — should be no-ops on a stage-1-built base, but
   makes stage 2 robust against externally-supplied bases).

8. **The ansible provisioner runs.** Packer:
   - Writes a temp inventory file: `default ansible_host=127.0.0.1
     ansible_user=packer ansible_port=<random>`
   - Sets env vars: `COMPLIANCE_PROFILE=cis-l1`, `FIPS_MODE=false`,
     `TENANT=bosch`, `IMAGE_VERSION=<...>`, `ANSIBLE_HOST_KEY_CHECKING=False`
   - Invokes `ansible-playbook -i <tmp> playbooks/packer-bake.yml`
     `--extra-vars ansible_python_interpreter=/usr/bin/python3 -v`
   - **`use_proxy = false`** — ansible connects directly, not through
     packer's SSH proxy. Requires the bake-time public key to be in the
     base's `authorized_keys` (which it is, courtesy of stage 1).

9. **`packer-bake.yml` runs:**
   - Asserts env vars are set (`COMPLIANCE_PROFILE` in `[cis-l1, cis-l2]`,
     `FIPS_MODE` in `[true, false]`, `TENANT` non-empty)
   - Updates the apt cache
   - Imports the `compliance` role with the tenant overrides (banner text,
     password policy, audit settings, AppArmor toggle)
   - Stamps `/etc/image-metadata` (tenant, profile, fips, version, base os)
   - Cleans apt cache, zeroes free space (improves qcow2 compressibility)

10. **Shutdown + export** — packer issues `shutdown_command`, qemu
    powers off cleanly, packer copies the qcow2 to
    `output/bosch/arm64/qemu/<IMAGE_VERSION>/bosch-ubuntu2204-cisl1-arm64-<IMAGE_VERSION>.qcow2`.

11. **Manifest** is written including `base_image_path`, so the artifact
    can be traced back to the exact base it was built from.

### What you should see in the log

- `==> packer init / validate / build` headers
- `==> Starting HTTP server on port ...` (still happens; serves nothing)
- `==> Starting VM with qemu binary` — VM boots from base qcow2
- `==> Waiting for SSH to become available...` — ~30 sec, no install
- `==> Provisioning with shell script: ...` (apt-get install)
- `==> Provisioning with Ansible...`
- ansible task headers stream by
- `==> Gracefully halting virtual machine`
- `Builds finished.`

---

## The `build.sh` wrapper, end-to-end

`scripts/build.sh` does five jobs:

1. **Argument & environment validation** — accepts `<tenant> <provider>
   [image_version]` positionally; reads `ARCH`, `STAGE`, `BASE_VERSION`,
   `BASE_IMAGE_PATH` from env. Refuses unknown values fail-loud.

2. **Tenant + arch dispatch** — picks the right template and var-file based
   on `<tenant>-${ARCH}` (e.g. `bosch-arm64` → two-stage path; `bosch-amd64`
   → legacy monolith path).

3. **SSH keypair management** — generates `keys/packer_ed25519` on first run,
   reuses thereafter. Renders `http/user-data` from `.tmpl` with the live
   pubkey before every build.

4. **Stage orchestration (arm64+bosch only):**
   - `STAGE=base` → calls `run_packer_build` for stage 1 only, updates
     `latest/` symlink
   - `STAGE=hardened` → resolves `BASE_IMAGE_PATH` (default vs explicit),
     refuses to run if base is missing, calls `run_packer_build` for stage 2
   - `STAGE=all` (default) → both, in order

5. **Packer invocation** via the `run_packer_build` helper:
   - `packer init` (downloads plugins)
   - `packer validate` (catches HCL/var errors before launching VMs)
   - `packer build -on-error=ask` (the `-on-error=ask` flag prompts
     `[c]lean / [a]bort / [r]etry` on failure instead of auto-cleaning the
     half-baked VM, so you can ssh in to inspect)

The legacy x86 path at the bottom of `build.sh` is unchanged from before
the split — runs `packer build -only=<src>` on the monolith template.

---

## Common workflows

### A) "I'm iterating on the compliance role and want fast feedback"

```bash
# First time only: bake a clean base
ARCH=arm64 STAGE=base ./scripts/build.sh bosch qemu     # ~12 min

# Then for every ansible iteration:
ARCH=arm64 STAGE=hardened ./scripts/build.sh bosch qemu # ~3 min
```

### B) "I want to use yesterday's half-baked qcow2 as the base (skip OS install entirely, no clean base yet)"

```bash
ARCH=arm64 STAGE=hardened \
  BASE_IMAGE_PATH=output/bosch/arm64/qemu/2026-05-03.1/bosch-ubuntu2204-cisl1-arm64-2026-05-03.1.qcow2 \
  ./scripts/build.sh bosch qemu                         # ~3 min
```

This is the right move when you have a usable disk in hand and don't want
to spend 12 min re-installing Ubuntu just to test an ansible change.

### C) "Full clean build from scratch (CI / release / verify-from-zero)"

```bash
# Removes existing keys, base, and outputs — start clean
rm -rf keys/ output/

ARCH=arm64 ./scripts/build.sh bosch qemu                # both stages, ~15-18 min
```

### D) "Refresh the base because Ubuntu cut a new point release"

```bash
# Update the ISO + checksum in variables/ubuntu-arm64-base.pkrvars.hcl
$EDITOR variables/ubuntu-arm64-base.pkrvars.hcl

# Bake a new base (gets its own date-versioned dir + becomes `latest`)
ARCH=arm64 STAGE=base ./scripts/build.sh bosch qemu

# Now stage 2 builds will pick up the new base via the `latest/` symlink
ARCH=arm64 STAGE=hardened ./scripts/build.sh bosch qemu
```

### E) "Override the version stamps for a release build"

```bash
ARCH=arm64 \
  BASE_VERSION=2026-05-04 \
  ./scripts/build.sh bosch qemu 2026-05-04.3
# IMAGE_VERSION (positional 3rd arg) → 2026-05-04.3 for the hardened image
# BASE_VERSION → 2026-05-04 for the base
```

### F) "Iterate on a failed build at the `[c]lean / [a]bort / [r]etry` prompt"

When a build fails (most likely in stage 2's ansible), packer pauses with:

```
[c] Clean up and exit, [a] abort without cleanup, or [r] retry step
```

- **`r`** — re-runs the failed step against the same (still-running) VM.
  Edit the failing playbook task in another terminal first; ansible re-reads
  it on retry. **Cheapest** iteration.
- **`a`** — keeps the half-baked qcow2 + VM around so you can SSH in
  manually for inspection (`ssh -i keys/packer_ed25519 packer@127.0.0.1
  -p <port>`). Then re-run with `STAGE=hardened BASE_IMAGE_PATH=<that-qcow2>`.
- **`c`** — default cleanup. Use when you just want to start over.

---

## The SSH key contract

Both stages use **the same** `keys/packer_ed25519` keypair. The contract:

| Component | Role |
|---|---|
| `keys/packer_ed25519.pub` | Substituted into `http/user-data` by `build.sh` on every run |
| Stage 1 cloud-init | Reads `user-data`, places the pubkey in `/home/packer/.ssh/authorized_keys` |
| Base qcow2 | Carries that authorized_keys entry forever |
| Stage 2 qemu source | `ssh_private_key_file = keys/packer_ed25519` |
| Stage 2 ansible provisioner | `use_proxy = false` → SSHes directly with the same private key |

**Implication:** if you regenerate the keypair (`rm -rf keys/`), the OLD
base qcow2's authorized_keys will reject new keys. You must re-bake the
base. This is intentional fail-loud behavior — the next stage 2 SSH attempt
will hit `Permission denied (publickey)` immediately, not silently work
with stale credentials.

---

## The `cloud-init` user-data contract

Stage 1 only. The flow:

```
http/user-data.tmpl           ← committed, source of truth
        │
        │  build.sh: awk substitutes @@SSH_PUBKEY@@ → contents of *.pub
        ▼
http/user-data                ← gitignored, regenerated every build
        │
        │  packer serves over HTTP at http://10.0.2.2:<port>/
        ▼
Ubuntu installer (Subiquity)  ← reads, executes
```

The `meta-data` file in `http/` is empty — required by the nocloud
datasource as a sibling of `user-data`. Don't delete it.

---

## Variable resolution and precedence

Both stages pass two var-files to packer plus several `-var` overrides:

```
packer build \
  -var-file=variables/common.pkrvars.hcl \             # 1. shared defaults
  -var-file=variables/<stage-specific>.pkrvars.hcl \   # 2. stage overrides
  -var "image_version=..." \                            # 3. wrapper-injected
  -var "ssh_private_key_file=..." \                     # 3. wrapper-injected
  -var "base_image_path=..." \                          # 3. (stage 2 only)
  templates/<stage-specific>.pkr.hcl
```

Packer evaluates in this order (later wins):
1. `default` in the template's `variable` block
2. First `-var-file`
3. Second `-var-file`
4. `-var` flags (left to right)

So you can override anything by passing a later `-var` on the command line —
useful for one-off experiments without editing the var-files.

**Common-vs-stage-specific split:**

| Var | common | base | hardened |
|---|---|---|---|
| `output_base_dir`, `image_version`, `ssh_timeout` | ✅ | | |
| `build_cpus`, `build_memory`, `disk_size_mb` | ✅ | uses | declares unused |
| `iso_url`, `iso_checksum` | | ✅ | not declared |
| `ssh_username`, `image_name_prefix` | | ✅ | ✅ (different prefix) |
| `tenant`, `compliance_profile`, `fips_mode` | | | ✅ |
| `login_banner`, `base_image_path` | | | ✅ |

`disk_size_mb` exists in `common.pkrvars.hcl` but stage 2 doesn't use it
(the disk is already sized by stage 1). The stage 2 template still declares
it as a variable so the var-file load doesn't error on "undeclared" —
declaring-but-not-using is fine in packer.

---

## Output directory layout

```
output/
├── base/
│   └── ubuntu2204-arm64/
│       ├── 2026-05-04/
│       │   ├── ubuntu2204-arm64-base-2026-05-04.qcow2
│       │   ├── ubuntu2204-arm64-base-latest.qcow2 → (stable name symlink)
│       │   └── manifest.json
│       └── latest → ../2026-05-04                       (build.sh maintains)
│
├── bosch/
│   └── arm64/
│       └── qemu/
│           └── 2026-05-04.1/
│               ├── bosch-ubuntu2204-cisl1-arm64-2026-05-04.1.qcow2
│               └── manifest.json
│
├── bosch/                                                (legacy x86 monolith)
│   └── (provider)/<version>/...
│
└── *.log                                                 (per-build packer logs)
```

Per-build logs are written to `output/<TENANT>-<ARCH>-<STAGE>-<VERSION>.log`
(e.g. `bosch-arm64-base-2026-05-04.log`,
`bosch-arm64-hardened-qemu-2026-05-04.1.log`). These are
debug-level packer traces (`PACKER_LOG=1`) — the most useful place to look
when a build fails silently.

---

## Failure modes per stage

### Stage 1 failure modes (OS install)

| Symptom | Likely cause |
|---|---|
| Tiny qcow2 (~192 KB), packer waits for SSH then times out | Autoinstall never ran. Boot command didn't reach GRUB → ISO live-server booted instead of installer |
| GRUB menu visible on screen but `packer build` exits with no install | Boot command keystrokes went to qemu monitor (missing `ramfb`/`virtio-gpu-pci`) |
| Subiquity starts but errors on user-data | `http/user-data` malformed — re-render from `.tmpl` |
| `Permission denied (publickey,password)` after install | `keys/packer_ed25519.pub` doesn't match what's in cloud-init's `authorized-keys` — re-render `user-data` |

For all the long-tail debugging behind these symptoms, the prior monolith
template's source comments document every gotcha (boot_wait timing, EFI
firmware paths, qemuargs aarch64 quirks, etc.) — those comments were
preserved verbatim in stage 1's template.

### Stage 2 failure modes (ansible)

| Symptom | Likely cause |
|---|---|
| `Permission denied (publickey)` immediately on stage 2 boot | Base qcow2 was built with a different keypair than `keys/packer_ed25519`. Re-bake base. |
| `object of type 'dict' has no attribute 'X'` | `packer-bake.yml` overrides `compliance:` at role-vars without including key X. Add it (the role's `defaults/main.yml` does NOT merge — see the inline comment in `packer-bake.yml`) |
| `No package matching 'X' is available` | Cross-distro package name mismatch in the role (RHEL `audit` vs Debian `auditd`). Use OS-keyed dict pattern in the role's `loop:` |
| `ansible_X` deprecated → use `ansible_facts['X']` | Ansible 12+ deprecation. Either pin to older ansible OR rewrite the playbook fact references |

When ansible fails, the `[c]lean / [a]bort / [r]etry` prompt is your friend
— don't `c`lean unless you really want to. `a`bort + ssh in + diagnose is
usually faster.

---

## What's parked for later

Tracked here so we don't lose them:

1. **Migrate amd64 (bosch + renesas) to two-stage.** Same pattern. The
   amd64 templates have BIOS/SeaBIOS quirks that differ from arm64 EFI but
   the structure carries over. Do this when you next iterate on either
   amd64 tenant.

2. **Re-add VirtualBox + VMware to stage 2.** Requires `virtualbox-ovf` and
   `vmware-vmx` source types (NOT `virtualbox-iso` and `vmware-iso` — those
   want an installer ISO). Stage 1 would also need parallel sources, OR
   stage 2 would convert the qemu-built qcow2 to OVA/VMX via a
   post-processor. Not blocking anyone today.

3. **Pin a SHA on `base_image_path`.** Currently `iso_checksum = "none"` in
   stage 2 with a packer warning. For tamper-detection / supply-chain
   trust, compute the base qcow2's SHA-256 once and pin it via a sidecar
   `.sha256` file that stage 2 reads.

4. **Ansible 12 deprecation cleanup.** `ansible_os_family` and friends are
   being removed in favor of `ansible_facts['os_family']`. Sweep the
   compliance role and `packer-bake.yml`.

5. **Refactor compliance role to flat leaf vars.** Replace
   `compliance: { profile, fips_mode, ... }` with
   `compliance_profile`, `compliance_fips_mode`, etc. so partial overrides
   merge cleanly with role defaults. Eliminates the "playbook must mirror
   every key" sharp edge documented in `packer-bake.yml`.

---

## See also

- `README.md` (this dir) — overview, x86 monolith path, ISO sourcing,
  arch-vs-tenant matrix
- `templates/bosch-ubuntu2204-arm64-hardened.pkr.hcl` — stage 2 template
  with detailed inline comments
- `templates/ubuntu2204-arm64-base.pkr.hcl` — stage 1 template
- `scripts/build.sh` — wrapper with all dispatch logic
- `../ansible/playbooks/roles/compliance/` — the role applied at stage 2
