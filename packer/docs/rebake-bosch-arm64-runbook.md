# Rebake Runbook — bosch ubuntu2204-cisl1-arm64 (qemu provider)

**Audience**: anyone shipping a new release of `nthedao2705/ubuntu2204-cisl1-arm64` after the 2026-05-20 bake-time fix landed.

**Working directory** for all commands: `~/Projects/Infrastrutures/devops-tools/packer`

**Total wall-clock time**: ~25–45 min (bake dominates; ~30 min for a hardened arm64 qemu rebuild).

**Conventions in this doc**:
- 🔀 **Decision point** — you choose which branch to take
- 🩹 **Recovery procedure** — what to do if a step fails
- 🚦 **Pass criterion** — must be green before proceeding to the next phase

---

## Why this runbook exists

The 2026-05-05 release of `nthedao2705/ubuntu2204-cisl1-arm64` (qemu provider) was unusable for external consumers due to three layered bake-time bugs:

| # | Layer | Bug | Consumer symptom |
|---|---|---|---|
| 1 | UEFI / NVRAM | `vagrant-qemu` 0.3.x ignores box-side NVRAM; ships an empty `edk2-arm-vars.fd`. Ubuntu's installer only writes `/EFI/ubuntu/grubaa64.efi` + an NVRAM `BootXXXX` entry — empty NVRAM = UEFI can't find grub | `vagrant up` hangs at UEFI; serial log stops after `Image at … start failed` lines |
| 2 | NIC bus | Plugin defaults to `virtio-net-device` (mmio); guest NIC is named `eth0`; netplan's `match: name: en*` ignores it → no DHCP | TCP port forwards but no SSH banner; `ip -brief link` shows `eth0 DOWN` only |
| 3 | authorized_keys | Subiquity autoinstall silently drops the 2nd entry in `ssh.authorized-keys` list; only the bake-time key landed; vagrant's insecure RSA pubkey was missing | `Permission denied (publickey)` for any consumer who doesn't have the bake-time private key |

Full diagnostic + sources:
`~/.claude/agent-memory/devops-architect/feedback_vagrant_qemu_consumer_boot_pitfalls.md`

The four files patched on 2026-05-20:
- `playbooks/packer-bake.yml` — three new post-tasks (EFI fallback, shim copy, vagrant authorized_key)
- `templates/box-vagrantfile.qemu.rb` — `qe.net_device` = `virtio-net-pci`
- `templates/bosch-ubuntu2204-arm64-hardened.pkr.hcl` — shell-local PP now writes `provider:libvirt` + dynamic `virtual_size` and ships `efivars.fd` in the bundle
- `.gitignore` — `smoke/` excluded

The smoke-test harness lives under `smoke/qemu-bosch-arm64/` (gitignored).

---

## Phase 0 — Preflight (5 min)

### 0.1 Verify all upstream fixes are in place

```bash
cd ~/Projects/Infrastrutures/devops-tools/packer

# Fix 1: virtio-net-pci in embedded box Vagrantfile
grep -n 'qe.net_device' templates/box-vagrantfile.qemu.rb
# expect: qe.net_device   = 'virtio-net-pci'

# Fixes 2 & 3: EFI fallback + vagrant key in bake playbook
grep -n -E 'BOOTAA64\.EFI|vagrant insecure' playbooks/packer-bake.yml
# expect: 3 lines — the file task, the copy task, the authorized_key task

# Fix 4: shell-local PP produces correct metadata.json + bundles efivars.fd
grep -n -E 'provider":"libvirt|virtual_size|efivars\.fd' \
  templates/bosch-ubuntu2204-arm64-hardened.pkr.hcl
# expect: at least 3 lines confirming the new PP body
```

🔀 **Decision**: If any expected line is missing, STOP. The fix wasn't applied — patch before continuing.

### 0.2 Sanity-check prerequisites

```bash
# Tooling
command -v packer    && packer version
command -v qemu-system-aarch64 && qemu-system-aarch64 --version | head -1
command -v ansible   && ansible --version | head -1
command -v vagrant   && vagrant --version
vagrant plugin list | grep -E 'qemu|vmware|virtualbox'
# expect: vagrant-qemu must be 0.3.x+

# Disk: re-bake needs ~12 GB free under packer/output/
df -h ~/Projects/Infrastrutures/devops-tools/packer/output/

# Ansible collections — authorized_key task needs ansible.posix
ansible-galaxy collection list 2>/dev/null | grep ansible.posix
# expect: ansible.posix 1.x or higher
```

🩹 If `ansible.posix` is missing:
```bash
ansible-galaxy collection install ansible.posix
```

### 0.3 Existing base image (if reusing for STAGE=hardened only)

```bash
ls -la output/base/ubuntu2204-arm64/*/ 2>/dev/null
```

### 0.4 Decide what to rebuild

🔀 **Decision — which STAGE to re-run?**

| Goal | STAGE | Why |
|---|---|---|
| Apply Ansible-only fixes (fastest, ~10 min) | `hardened` | Re-uses existing base qcow2; just re-runs compliance role + new post-tasks |
| Refresh everything from scratch (~30 min) | `all` | New OS install + new hardened layer |
| Try to fix a base-image issue | `base` then `hardened` | Two-step |

**Recommended for this fix**: `STAGE=hardened`. All three bake-time fixes are in post-tasks / embedded Vagrantfile / shell-local PP — none of them require a new base install.

---

## Phase 1 — Re-bake (10–30 min depending on STAGE)

### 1.1 Set required environment

```bash
# Pick a NEW version. Format YYYY-MM-DD.N
export NEW_VER=2026-05-20.1

# If using existing base: confirm its path
export BASE_VERSION=$(ls -1 output/base/ubuntu2204-arm64/ | sort -r | head -1)
echo "BASE_VERSION=$BASE_VERSION"   # e.g. 2026-05-03
```

### 1.2 Run the bake

```bash
ARCH=arm64 STAGE=hardened \
  BASE_VERSION="$BASE_VERSION" \
  ./scripts/build.sh bosch qemu "$NEW_VER" 2>&1 \
  | tee /tmp/bake-${NEW_VER}.log
```

🚦 **Watch for these success signals in the log:**

| Marker | Meaning |
|---|---|
| `==> qemu.bosch-ubuntu2204-arm64: Booting from disk` | Hardened image boots |
| `TASK [Bake \| install GRUB shim at UEFI fallback path...]` → `changed` | **Fix #1 applied** |
| `TASK [Bake \| authorize Vagrant's well-known insecure RSA pubkey...]` → `changed` | **Fix #3 applied** |
| `==> qemu.bosch-ubuntu2204-arm64: Running post-processor: shell-local` followed by a `tar -tzf` listing **4 files** (`metadata.json`, `Vagrantfile`, `box.img`, `efivars.fd`) | **Fix #4 (PP) applied** |
| Final line: `Builds finished. The artifacts of successful builds are:` | bake succeeded |

🩹 **Common failure modes**:

| Symptom | Cause | Recovery |
|---|---|---|
| `PACKER_LOG_PATH directory missing` | Wrapper bug — log path's parent doesn't exist | `mkdir -p output/` and retry |
| `ansible.posix.authorized_key: collection not found` | Missing Ansible collection | `ansible-galaxy collection install ansible.posix` |
| `qemu-img info: parse failed` | New shell-local PP's awk couldn't read virtual size | Run `qemu-img info <output>.qcow2` manually. If it reports differently than `virtual size: NN GiB (…)`, file an issue — harden the awk |
| Bake-host out of memory | Default `build_cpus`/`build_memory` too aggressive | Reduce in `variables/bosch-arm64.pkrvars.hcl` |

### 1.3 Confirm outputs

```bash
ls -la output/bosch/arm64/qemu/${NEW_VER}/
# expect:
#   bosch-ubuntu2204-cisl1-arm64-${NEW_VER}.box       (~1.6 GB)
#   bosch-ubuntu2204-cisl1-arm64-${NEW_VER}.qcow2     (~4 GB)
#   efivars.fd                                        (64 MB)
#   manifest.json
```

Then **verify the box bundle structure**:

```bash
tar -tzf output/bosch/arm64/qemu/${NEW_VER}/bosch-ubuntu2204-cisl1-arm64-${NEW_VER}.box
# expect EXACTLY:
#   metadata.json
#   Vagrantfile
#   box.img
#   efivars.fd

tar -xzOf output/bosch/arm64/qemu/${NEW_VER}/bosch-ubuntu2204-cisl1-arm64-${NEW_VER}.box \
  metadata.json
# expect: {"provider":"libvirt","format":"qcow2","architecture":"arm64","virtual_size":40}
#                                                                       ↑
#                                       integer matches qemu-img info value
```

🚦 **Pass criterion for Phase 1**: 4-file bundle structure verified, metadata.json shows `provider:libvirt` + non-zero `virtual_size`.

🔀 If any structural check fails: do NOT proceed. The shell-local PP didn't take effect — re-run with `-only=qemu.*` or inspect the bake log around `post-processor: shell-local`.

---

## Phase 2 — Verify (5 min total)

Two tiers — run them in order. **Both must pass before publishing.**

### 2.1 Tier A — direct-qemu verification (proves all 3 bake fixes)

```bash
# This boots the qcow2 directly with an EMPTY NVRAM — proves the EFI fallback
# path works, the NIC comes up, and the vagrant key landed.
./smoke/qemu-bosch-arm64/verify-bake-fixes.sh ${NEW_VER}
```

🚦 **Expected final block**:
```
[PASS] F2 — virtio-net-pci → NIC is enp0sN (matches netplan en*)
[PASS] F1 — EFI fallback path baked in (/EFI/BOOT/BOOTAA64.EFI exists)
[PASS] F3 — vagrant insecure RSA pubkey is in /home/packer/.ssh/authorized_keys
==================== 3/3 bake fixes confirmed ====================
All three bake fixes verified. Safe to upload + release.
```

🩹 **If any check FAILs**:

| FAIL | Cause | Recovery |
|---|---|---|
| F1 (no BOOTAA64.EFI) | Ansible task didn't run | Check bake log for `Bake \| install GRUB shim`; confirm `ansible_architecture == "aarch64"` matched at bake time |
| F2 (NIC is `eth0`, not `enp0sN`) | `box-vagrantfile.qemu.rb` wasn't picked up by shell-local PP | `tar -xzOf <box> Vagrantfile \| grep net_device` — must show `virtio-net-pci`. If not, the embedded Vagrantfile is stale |
| F3 (vagrant key missing) | `ansible.posix.authorized_key` task didn't run | Collection missing? Check bake log; also confirm task ran on Debian family (the `when:` clause) |

### 2.2 Tier B — vagrant integration (proves consumer experience)

First **swap to the stripped-down Vagrantfile** — this proves the bake fixes work WITHOUT consumer-side workarounds:

```bash
cd smoke/qemu-bosch-arm64
mv Vagrantfile Vagrantfile.with-workarounds
cp Vagrantfile.stripped Vagrantfile
cd -

# Run the existing smoke harness — same as before, but the Vagrantfile is now
# the minimal one a real consumer would write.
./smoke/qemu-bosch-arm64/smoke-vagrant.sh
```

🚦 **Expected**: same `SMOKE TEST PASS` output as before, but **without** the `[nvram-patch] overwrote ...` line (because no trigger).

🩹 **If Tier B fails but Tier A passed**: the consumer-side workarounds ARE compensating for an unfixed bake issue. Restore the workarounds (`mv Vagrantfile.with-workarounds Vagrantfile`) and investigate which fix didn't take effect — usually F2 (the embedded Vagrantfile didn't pick up the new template).

🔀 **Optional**: also run `./smoke/qemu-bosch-arm64/smoke-manual.sh` against the new artifact to triple-confirm.

---

## Phase 3 — Re-upload + Release (5 min)

### 3.1 Set auth env (HCP service principal)

```bash
# These should be in your shell init or a sourced .env — recheck they're set:
echo "HCP_CLIENT_ID set?:     ${HCP_CLIENT_ID:+yes}"
echo "HCP_CLIENT_SECRET set?: ${HCP_CLIENT_SECRET:+yes}"
echo "VAGRANT_CLOUD_ORG:      ${VAGRANT_CLOUD_ORG:-(unset — using default)}"

# Critical: must be the REGISTRY slug, not the HCP org slug
export VAGRANT_CLOUD_ORG="nthedao2705"
```

### 3.2 Upload — qemu first

```bash
./scripts/publish.sh bosch ${NEW_VER} --providers qemu 2>&1 \
  | tee /tmp/publish-qemu-${NEW_VER}.log
```

🚦 **Watch for**:
- `==> auth: HCP service principal` — auth mode confirmed
- `==> box: Creating box…` or `already exists — tolerated` — idempotent path works
- `==> version: Creating version… ${NEW_VER}` or tolerated 422
- `==> provider: Creating provider qemu (arm64)` or tolerated 422
- `==> uploading file…` followed by `Upload succeeded` — the big upload

🩹 **Failure modes**:

| Symptom | Cause | Recovery |
|---|---|---|
| `An invalid option was specified` on `provider upload` | positional arg order regression | `publish.sh` ~line 290 must be `<box> <provider> <version> <architecture> <file>` — see `feedback_vagrant_cloud_cli_24x_signatures.md` |
| `Vagrant Cloud request failed - registry not found` | `VAGRANT_CLOUD_ORG` wrong | Must be `nthedao2705` (registry slug), NOT `nthedao2705-org` (HCP org slug). See `feedback_vagrant_cloud_hcp_auth.md` |
| `401 Unauthorized` | Service principal expired / wrong scope | Re-create the HCP IAM service principal key; Contributor role required |

### 3.3 Upload virtualbox (optional — only if you re-baked vbox too)

```bash
# Only if you ran build.sh with provider=virtualbox or all
# If you didn't re-bake vbox, skip this and the existing vbox upload stays valid
./scripts/publish.sh bosch ${NEW_VER} --providers virtualbox
```

### 3.4 Release the version

After both Tier A + Tier B passed and uploads completed:

```bash
./scripts/publish.sh bosch ${NEW_VER} --release
```

This flips the version state from `unreleased` to `active`. **Both providers release atomically.**

🩹 **Release-while-locked**: HCP sometimes briefly locks a version while uploads finalize. If `release` fails with HTTP 409 or "version is being processed", wait 30s and retry.

---

## Phase 4 — Post-release verification (3 min)

### 4.1 Simulate a registry consumer

This proves a fresh engineer who runs `vagrant init nthedao2705/...` gets a working box. **This is the real production-readiness gate.**

```bash
TMPDIR=$(mktemp -d)
cd "$TMPDIR"

# Force pull from registry, NOT local cache
vagrant box remove nthedao2705/ubuntu2204-cisl1-arm64 --all --force 2>/dev/null || true
vagrant init nthedao2705/ubuntu2204-cisl1-arm64

# Minimum patch — disable synced folder + bump timeout (a real consumer
# might not know about the macOS SMB quirk, but for this validation we sidestep it)
cat > Vagrantfile <<'EOF'
Vagrant.configure("2") do |config|
  config.vm.box              = "nthedao2705/ubuntu2204-cisl1-arm64"
  config.vm.box_architecture = "arm64"
  config.vm.synced_folder ".", "/vagrant", disabled: true
  config.vm.boot_timeout = 300
end
EOF

vagrant up --provider qemu
vagrant ssh -c 'cat /etc/image-metadata'
vagrant halt && vagrant destroy -f

cd - && rm -rf "$TMPDIR"
```

🚦 **Pass criterion**: `vagrant up` reaches `Machine booted and ready!` and `vagrant ssh` returns `image_version=${NEW_VER}`.

### 4.2 Tag in git

```bash
cd ~/Projects/Infrastrutures/devops-tools
git add packer/playbooks/packer-bake.yml \
        packer/templates/box-vagrantfile.qemu.rb \
        packer/templates/bosch-ubuntu2204-arm64-hardened.pkr.hcl \
        packer/.gitignore \
        packer/docs/rebake-bosch-arm64-runbook.md \
        packer/smoke/qemu-bosch-arm64/Vagrantfile \
        packer/smoke/qemu-bosch-arm64/Vagrantfile.stripped \
        packer/smoke/qemu-bosch-arm64/verify-bake-fixes.sh \
        packer/smoke/qemu-bosch-arm64/smoke-vagrant.sh \
        packer/smoke/qemu-bosch-arm64/smoke-manual.sh
git commit -m "fix(packer): NVRAM fallback, virtio-net-pci, vagrant key — release ${NEW_VER}"
git tag -a "bosch-arm64-${NEW_VER}" \
        -m "bosch ubuntu2204-cisl1-arm64 release ${NEW_VER} — all 3 bake fixes in"
git push && git push --tags
```

### 4.3 Record the release in the Obsidian vault

```bash
# Option A — ADR (architectural commitment):
#   /save-decision bosch-arm64-bake-fixes "Bake-time fixes for vagrant-qemu consumer flow"
#
# Option B — session digest (operational record):
#   write 50-conversations/2026-05-20-bosch-arm64-rebake.md with frontmatter
#   type: conversation, plus Goal / What we did / Decisions / Files touched.
```

---

## Phase 5 — Cleanup follow-ups (non-blocking)

### 5.1 Make the stripped Vagrantfile canonical
Once Tier B passed (Phase 2.2), drop the workarounds permanently:
```bash
cd smoke/qemu-bosch-arm64
rm Vagrantfile.with-workarounds
# Vagrantfile is already the stripped version from Phase 2.2
```

### 5.2 Mirror to the virtualbox source (if not already done)
The vbox bake doesn't have the same UEFI/NIC issues (it ships its own vagrant PP and net config), but the `authorized_key` fix should still apply. Check `templates/bosch-ubuntu2204-hardened.pkr.hcl` (or the equivalent vbox post-tasks) for parity.

### 5.3 Optional — pin the qemu firmware version
We currently rely on Homebrew's `/opt/homebrew/share/qemu/edk2-aarch64-code.fd`. A `brew upgrade qemu` could ship a slightly different EDK2 build → potential NVRAM compatibility regression. Consider vendoring a known-good firmware copy under `packer/firmware/` and pointing both Packer + smoke harness at that vendored path.

### 5.4 Document the diagnostic harness as a reference
The five scripts in `smoke/qemu-bosch-arm64/` (`smoke-manual.sh`, `smoke-vagrant.sh`, `verify-bake-fixes.sh`, `probe-ssh-with-build-key.sh`, `probe-authkeys.exp`) plus `Vagrantfile.stripped` are now a permanent **regression test suite**. Consider:
- Adding a `smoke/README.md` describing each script's purpose + when to use it
- Wiring `verify-bake-fixes.sh` as a gate inside `build.sh` itself (auto-runs after a successful bake)
- Adding to CI once you have a self-hosted Apple Silicon runner

---

## Quick-reference — files touched by the 2026-05-20 fix

| File | Change | Lines (approx) |
|---|---|---|
| `playbooks/packer-bake.yml` | +3 post_tasks (EFI fallback dir, shim copy, vagrant authorized_key) | +45 |
| `templates/box-vagrantfile.qemu.rb` | `qe.net_device` → `virtio-net-pci` + comment block | +5 |
| `templates/bosch-ubuntu2204-arm64-hardened.pkr.hcl` | shell-local PP: `provider:libvirt`, dynamic `virtual_size`, ship `efivars.fd` | +15 |
| `.gitignore` | `smoke/` excluded | +1 |
| `docs/rebake-bosch-arm64-runbook.md` | THIS FILE (new) | new |
| `smoke/qemu-bosch-arm64/Vagrantfile` | Consumer smoke Vagrantfile (with workarounds — pre-bake state) | new |
| `smoke/qemu-bosch-arm64/Vagrantfile.stripped` | Minimal consumer Vagrantfile — post-bake state | new |
| `smoke/qemu-bosch-arm64/verify-bake-fixes.sh` | Direct-qemu in-guest verification of all 3 fixes | new |
| `smoke/qemu-bosch-arm64/smoke-vagrant.sh` | End-to-end vagrant smoke test (~1 min) | new |
| `smoke/qemu-bosch-arm64/smoke-manual.sh` | Bypass-vagrant qemu boot + SSH probe | new |
| `smoke/qemu-bosch-arm64/probe-*.{sh,exp}` | Diagnostic helpers | new |

Backups still in place at `output/bosch/arm64/qemu/2026-05-05.1/*.box.bak2` (the original broken `.box`).

---

## Background reading

- `~/.claude/agent-memory/devops-architect/feedback_vagrant_qemu_consumer_boot_pitfalls.md` — full diagnostic ladder + sources for the three bugs
- `~/.claude/agent-memory/devops-architect/feedback_vagrant_cloud_hcp_auth.md` — HCP service principal auth model
- `~/.claude/agent-memory/devops-architect/feedback_vagrant_cloud_cli_24x_signatures.md` — `vagrant cloud` CLI 2.4.x signature changes
- `~/.claude/agent-memory/devops-architect/feedback_packer_vagrant_pp_no_qemu.md` — why metadata.json provider must be `libvirt` for vagrant-qemu
- `packer/docs/build-and-publish-runbook.md` — general build/publish reference (this doc is the arm64-specific addendum)
- `packer/docs/vagrant-cloud-publish.md` — publish.sh details
- vagrant-qemu plugin source: https://github.com/ppggff/vagrant-qemu
- Ubuntu autoinstall reference: https://canonical-subiquity.readthedocs-hosted.com/en/latest/reference/autoinstall-reference.html

---

## Appendix — Why each fix is a bake-time fix, not a consumer-side fix

| Fix | Why it MUST be done at bake time |
|---|---|
| F1 — EFI fallback path | `vagrant-qemu 0.3.x` hardcodes the bundled empty NVRAM at `import`; no consumer-side override exists. The only durable fix is making the qcow2 itself NVRAM-independent via UEFI's standard removable-media fallback (`/EFI/BOOT/BOOTAA64.EFI`) |
| F2 — virtio-net-pci | The embedded box `Vagrantfile` carries the qemu defaults. Consumers can override but shouldn't have to — every consumer would hit this otherwise. The PCI NIC name also matches what Packer's bake-time NIC was, so the netplan match works in BOTH contexts |
| F3 — vagrant insecure pubkey | Without it, no consumer-side fix exists short of telling everyone "use this private key" (which we can't ship publicly — and the bake key is in the wrong format anyway). The insecure RSA pubkey IS public knowledge from HashiCorp; landing it in `authorized_keys` is the only sane path |

All three are bake-time because they affect the **interior** of the consumer experience — anything we'd do on the consumer side would shift the burden from "ship one good box" to "every consumer must learn the workarounds." That's not a viable contract for a published registry box.
