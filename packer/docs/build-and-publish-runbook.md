# Runbook — bake & publish a Vagrant box (Apple Silicon, arm64)

End-to-end procedure for going from **clean checkout** to **publicly released
Vagrant box on Vagrant Cloud**, for both the `virtualbox` and `qemu`
providers, on the `arm64` architecture.

This is the operational thread tying the two reference docs together:

- [`BUILD-WORKFLOW.md`](./BUILD-WORKFLOW.md) — Stage-1 / Stage-2 Packer internals
- [`vagrant-cloud-publish.md`](./vagrant-cloud-publish.md) — Vagrant Cloud publish theory & alternatives

If you only want the happy-path commands, jump to
[§3 The end-to-end happy path](#3-the-end-to-end-happy-path). The rest of this
doc is the *why* and the *what-if-it-breaks* around those commands.

---

## Table of contents

1. [Mental model](#1-mental-model)
2. [Pre-flight — one-time setup](#2-pre-flight--one-time-setup)
3. [The end-to-end happy path](#3-the-end-to-end-happy-path)
4. [Step detail](#4-step-detail)
   - [4.1 Bake Stage 1 (base ISO install)](#41-bake-stage-1-base-iso-install)
   - [4.2 Bake Stage 2 (hardened, both providers)](#42-bake-stage-2-hardened-both-providers)
   - [4.3 Verify the artifacts](#43-verify-the-artifacts)
   - [4.4 Local smoke-test before publish](#44-local-smoke-test-before-publish)
   - [4.5 Dry-run the publish](#45-dry-run-the-publish)
   - [4.6 Publish (upload, NOT released)](#46-publish-upload-not-released)
   - [4.7 Release](#47-release)
5. [Common variations](#5-common-variations)
6. [Re-run, recovery, and idempotency](#6-re-run-recovery-and-idempotency)
7. [Troubleshooting matrix](#7-troubleshooting-matrix)
8. [What this runbook is NOT](#8-what-this-runbook-is-not)

---

## 1. Mental model

```
                  ┌──────────────┐
                  │  Stage 1     │   ~12-15 min
   Ubuntu ARM64   │  build.sh    │   produces base.qcow2 (tenant-agnostic)
   live ISO ────▶ │  STAGE=base  │
                  └──────┬───────┘
                         │
                         ▼
                  ┌──────────────┐
                  │  Stage 2     │   ~3 min  (run TWICE — once per provider)
   base.qcow2 ──▶ │  build.sh    │   PROVIDER=qemu       → qcow2 + .box
                  │STAGE=hardened│   PROVIDER=virtualbox → ova   + .box
                  └──────┬───────┘
                         │
                         ▼
                  ┌──────────────┐
                  │  publish.sh  │   ~30s for box/version create
   .box files ──▶ │  Vagrant     │   + ~30s-2min per upload
                  │  Cloud       │   default: NOT released
                  └──────┬───────┘
                         │
                         ▼
                    smoke test
                         │
                         ▼
                  ┌──────────────┐
                  │  publish.sh  │   flips version to "released"
                  │  --release   │   visible to `vagrant up` consumers
                  └──────────────┘
```

**Three properties that matter operationally:**

1. **Stage 1 is reusable.** A successful base lives forever (well, until a
   CVE forces a rebake). Stage 2 alone is what runs every iteration.
2. **Both providers consume the same Stage 1 base.** Re-baking Stage 2 for
   `virtualbox` does not invalidate the qemu artifact, and vice versa.
3. **Upload is decoupled from release.** `publish.sh` uploads always;
   `--release` is the explicit human-in-the-loop gate. This lets you smoke
   test the uploaded box before consumers can `vagrant up` it.

---

## 2. Pre-flight — one-time setup

Skip this section if you've published before. Everything here is set-and-forget.

### 2.1 Required tools on the bake host (macOS Apple Silicon)

```bash
brew install hashicorp/tap/packer  hashicorp/tap/vagrant  qemu  ansible
brew install --cask virtualbox     # for the virtualbox provider path
```

Sanity check:

```bash
packer  version             # >= 1.10
vagrant version             # >= 2.4 (multi-arch support)
qemu-system-aarch64 --version
VBoxManage --version
ansible --version
```

### 2.2 Vagrant Cloud account + API token

1. Create / log in at <https://app.vagrantup.com/>.
2. Account → **Security** → API tokens → **Create token** (scope: write).
3. Copy the `atlasv1.…` value — **HashiCorp shows it once**.

Set it in your shell profile (`~/.zshrc` or `~/.bashrc`):

```bash
export VAGRANT_CLOUD_TOKEN="atlasv1.xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
```

Alternatively, cache it via the CLI:

```bash
vagrant cloud auth login            # prompts for username + token
```

`publish.sh` accepts either form.

### 2.3 (qemu consumers only) install the consumer-side plugin

Anyone who will `vagrant up --provider qemu` needs:

```bash
vagrant plugin install vagrant-qemu
```

This is consumer-side, not bake-side. The bake host doesn't need the plugin.

### 2.4 Confirm the working directory

All commands below run from the `packer/` directory:

```bash
cd /Users/thedao/Documents/Self/Projects/Infrastrutures/devops-tools/packer
```

### 2.5 (optional) Override defaults via env

`publish.sh` has sensible defaults but accepts overrides:

| Env var | Default | Purpose |
|---|---|---|
| `VAGRANT_CLOUD_ORG` | `<tenant>` | The org/user the box lives under (the part before the slash in `bosch/ubuntu2204-cisl1-arm64`). |
| `BOX_NAME` | `ubuntu2204-cisl1-arm64` | The part after the slash. |
| `IMAGE_NAME_PREFIX` | `<tenant>-<BOX_NAME>` | Local artifact filename prefix. Match what Packer wrote. |
| `BOX_DESCRIPTION_FILE` | `docs/box-description.md` | Long-form markdown for the box's overview page. Optional. |

If you publish under your **personal** Vagrant Cloud account instead of an
org, override `VAGRANT_CLOUD_ORG` to your username — the org has to exist
*and you must have write access to it*.

---

## 3. The end-to-end happy path

For the `bosch` tenant on `arm64`, with version `2026-05-06.1`, releasing both
providers — the entire procedure in 7 commands:

```bash
cd packer

# 1. Stage 1 — base ISO install (only when missing or stale)
TENANT=bosch ARCH=arm64 STAGE=base IMAGE_VERSION=2026-05-06.1 \
  ./scripts/build.sh

# 2. Stage 2 — both providers (qemu + virtualbox), hardened
TENANT=bosch ARCH=arm64 STAGE=hardened PROVIDER=all \
  IMAGE_VERSION=2026-05-06.1 ./scripts/build.sh

# 3. Quick artifact verification
ls -lh output/bosch/arm64/{qemu,virtualbox}/2026-05-06.1/*.box

# 4. Local smoke test (qemu — fast)
vagrant box add --name bosch/ubuntu2204-cisl1-arm64 \
  output/bosch/arm64/qemu/2026-05-06.1/bosch-ubuntu2204-cisl1-arm64-2026-05-06.1.box \
  --architecture arm64 --force
# … vagrant init / vagrant up / vagrant destroy …

# 5. Dry-run publish (no API writes)
./scripts/publish.sh bosch 2026-05-06.1 --dry-run

# 6. Real upload (DOES write to Vagrant Cloud, but does NOT release)
./scripts/publish.sh bosch 2026-05-06.1

# 7. Release once you're satisfied with the smoke test
./scripts/publish.sh bosch 2026-05-06.1 --release
```

That's the whole thing. The rest of the doc explains what each command does
and how to recover when one fails.

---

## 4. Step detail

### 4.1 Bake Stage 1 (base ISO install)

**Purpose:** install Ubuntu 22.04 ARM64 from the live ISO into a clean
qcow2. Tenant-agnostic. Driven by `templates/ubuntu2204-arm64-base.pkr.hcl`
+ cloud-init autoinstall.

**Command:**

```bash
TENANT=bosch ARCH=arm64 STAGE=base IMAGE_VERSION=2026-05-06.1 \
  ./scripts/build.sh
```

> **Note:** `TENANT=bosch` here is a label only — Stage 1 doesn't apply
> tenant policy. The same base.qcow2 will be reused by every tenant's Stage 2.
> Some teams set `TENANT=base` for clarity; either works.

**Time:** ~12–15 min on M-series with HVF acceleration. Most of that is the
unattended Ubuntu installer.

**Output:** `output/base/arm64/qemu/<IMAGE_VERSION>/*.qcow2`

**Skip Stage 1 if:**

- A recent base.qcow2 exists at the path above and you're satisfied with its
  package versions / patches.
- You're iterating on the Stage 2 ansible role only.

**Don't skip Stage 1 if:**

- A new CVE was disclosed against the base distro and you want fresh patches.
- The Ubuntu live ISO was updated upstream.
- It's been > 1 month since the last base bake (rule of thumb).

Detailed Stage-1 internals — [`BUILD-WORKFLOW.md` § Stage 1](./BUILD-WORKFLOW.md#stage-1--bake-the-base-os-only-no-ansible).

### 4.2 Bake Stage 2 (hardened, both providers)

**Purpose:** boot the Stage 1 base, run the tenant's compliance ansible
role, snapshot the result. Wrap into provider-specific deliverables.

**Command (both providers in one call):**

```bash
TENANT=bosch ARCH=arm64 STAGE=hardened PROVIDER=all \
  IMAGE_VERSION=2026-05-06.1 ./scripts/build.sh
```

`PROVIDER=all` runs the qemu and virtualbox builds **sequentially** in the
same `packer build` invocation; both write to their own output subdirs and
neither blocks the other if one fails (Packer reports both results at the
end).

**Or run them independently:**

```bash
PROVIDER=qemu       … ./scripts/build.sh    # ~3 min
PROVIDER=virtualbox … ./scripts/build.sh    # ~3 min
```

**Time:** ~3 min per provider on a warm Stage 1 base.

**Output (both providers, each wrapped as a Vagrant `.box`):**

```
output/bosch/arm64/
├── qemu/2026-05-06.1/
│   ├── bosch-ubuntu2204-cisl1-arm64-2026-05-06.1.qcow2   ← raw disk
│   ├── bosch-ubuntu2204-cisl1-arm64-2026-05-06.1.box     ← wrapped, ready to publish
│   ├── efivars.fd
│   └── manifest.json
└── virtualbox/2026-05-06.1/
    ├── bosch-ubuntu2204-cisl1-arm64-2026-05-06.1.ova
    ├── bosch-ubuntu2204-cisl1-arm64-2026-05-06.1.box     ← wrapped, ready to publish
    └── manifest.json
```

**How the `.box` files get produced:**

- **virtualbox** — Packer's stock `vagrant` post-processor handles it.
- **qemu** — a `shell-local` post-processor in the template hand-assembles
  the tar (`metadata.json` + `Vagrantfile` + `box.img`) because the stock
  `vagrant` PP doesn't support `provider=qemu`. The static Vagrantfile
  shipped inside the box lives at `templates/box-vagrantfile.qemu.rb`.

Detailed Stage-2 internals — [`BUILD-WORKFLOW.md` § Stage 2](./BUILD-WORKFLOW.md#stage-2--apply-hardening-ansible-only-no-os-install).
The qemu wrapping rationale — [`vagrant-cloud-publish.md` § 2](./vagrant-cloud-publish.md#2-producing-a-providerqemu-box-from-the-qcow2).

### 4.3 Verify the artifacts

Before pushing anything to a registry, confirm the files exist and look right:

```bash
# both .box files present
ls -lh output/bosch/arm64/{qemu,virtualbox}/2026-05-06.1/*.box

# expected sizes: ~1.5 GB each (compressed Ubuntu 22.04 + tenant policy)
# substantially smaller (< 500 MB) → likely autoinstall failed silently
# substantially larger (> 4 GB)    → loose vagrant-disabled cleanup

# inspect the qemu box's metadata.json — quick sanity check
tar -xzOf output/bosch/arm64/qemu/2026-05-06.1/*.box metadata.json
# expect: {"provider":"qemu","format":"qcow2","architecture":"arm64"}

# inspect the virtualbox box's metadata.json
tar -xzOf output/bosch/arm64/virtualbox/2026-05-06.1/*.box metadata.json
# expect: {"provider":"virtualbox"}   (architecture absent — vbox PP doesn't write it)
```

If `metadata.json` is missing or `provider` is wrong, the consumer's
`vagrant up --provider <X>` will fail-fast with a "no provider for arch"
error. **Do not push.** Re-bake.

### 4.4 Local smoke-test before publish

Catching a broken box on your laptop is 100x cheaper than catching it from
a remote consumer's `vagrant up` failure. Always run at least one provider
locally before flipping `--release`.

```bash
# QEMU smoke test (fastest path — no GUI)
vagrant box add --name bosch/ubuntu2204-cisl1-arm64 \
  output/bosch/arm64/qemu/2026-05-06.1/bosch-ubuntu2204-cisl1-arm64-2026-05-06.1.box \
  --architecture arm64 --force

mkdir -p /tmp/bosch-smoke && cd /tmp/bosch-smoke
cat > Vagrantfile <<'RUBY'
Vagrant.configure('2') do |c|
  c.vm.box = 'bosch/ubuntu2204-cisl1-arm64'
  c.vm.box_architecture = 'arm64'
end
RUBY

vagrant up --provider qemu
vagrant ssh -c 'uname -a; cat /etc/os-release | head -2'
vagrant destroy -f
cd - && rm -rf /tmp/bosch-smoke
vagrant box remove bosch/ubuntu2204-cisl1-arm64 --architecture arm64 --provider qemu
```

If `vagrant ssh` works and the OS reports correctly, the box is good. If
SSH hangs > 60 s, the cloud-init / first-boot side is broken — investigate
before publishing.

(Optional) repeat with `--provider virtualbox` for symmetry.

### 4.5 Dry-run the publish

`publish.sh` has a `--dry-run` flag that prints every API call it would
make without executing any of them:

```bash
./scripts/publish.sh bosch 2026-05-06.1 --dry-run
```

What you should see:

```
[1/4] vagrant cloud box create bosch/ubuntu2204-cisl1-arm64 --short-description … --private
[2/4] vagrant cloud version create bosch/ubuntu2204-cisl1-arm64 2026-05-06.1 --description Build 2026-05-06.1
[3/4] virtualbox provider create + upload  (1.5G)  arch=arm64 --no-default-architecture
[3/4] qemu       provider create + upload  (1.5G)  arch=arm64 --no-default-architecture
[4/4] release SKIPPED (default)
```

If a provider is missing from the dry-run output, its `.box` file isn't on
disk for that version. Fix that before proceeding.

### 4.6 Publish (upload, NOT released)

Same command without `--dry-run`:

```bash
./scripts/publish.sh bosch 2026-05-06.1
```

This:

1. **Creates the box** on Vagrant Cloud if it doesn't exist (`bosch/ubuntu2204-cisl1-arm64`).
2. **Creates the version** if it doesn't exist (`2026-05-06.1`).
3. **For each `.box` on disk**, creates the provider entry and uploads.
4. **Stops short of `release`.** The version remains in `unreleased` state.

Time: ~30 s for steps 1–2, then ~30 s–2 min per provider depending on
upload bandwidth. Re-runs are idempotent — see [§6](#6-re-run-recovery-and-idempotency).

**Verify the upload landed:**

```bash
vagrant cloud box show bosch/ubuntu2204-cisl1-arm64
vagrant cloud version show bosch/ubuntu2204-cisl1-arm64 2026-05-06.1
```

You should see the version listed and both providers listed *under* it,
each with a non-zero `size` and status `active`.

Or browse: <https://app.vagrantup.com/bosch/boxes/ubuntu2204-cisl1-arm64>.

### 4.7 Release

After smoke test passes — even if you smoke-tested in 4.4, run **one more**
end-to-end pull from the registry to make sure the upload itself wasn't
corrupted:

```bash
vagrant box remove bosch/ubuntu2204-cisl1-arm64 --all-providers --force 2>/dev/null || true
vagrant box add bosch/ubuntu2204-cisl1-arm64 \
  --architecture arm64 --provider qemu --box-version 2026-05-06.1 --force
# (the version may not be findable until you release — that's fine, see note)
```

> **Note on unreleased versions and `box add`:** `vagrant box add` cannot
> pull an unreleased version by name from the registry. To round-trip-test
> *before* release, either pull from the local file (which we did in 4.4)
> or temporarily pass `--force` with the file URL. Once released, `box add`
> by name works.

Now flip the release switch:

```bash
./scripts/publish.sh bosch 2026-05-06.1 --release
```

`publish.sh` re-runs all the prior steps (idempotent) and adds:

```
[4/4] vagrant cloud version release bosch/ubuntu2204-cisl1-arm64 2026-05-06.1
```

The version is now visible to `vagrant up`. Anyone with the box tag can
pull it.

---

## 5. Common variations

### 5.1 Re-bake only Stage 2 (most common)

You changed the ansible compliance role and want to re-test:

```bash
# fast iteration — Stage 1 base is unchanged
TENANT=bosch ARCH=arm64 STAGE=hardened PROVIDER=qemu \
  IMAGE_VERSION=2026-05-06.2 ./scripts/build.sh
```

Bump the patch number (`.1` → `.2`) so the new artifact lives in its own
subdir. Don't overwrite a published version — once released, the
`(box, version)` pair is immutable on Vagrant Cloud.

### 5.2 Single provider only

```bash
TENANT=bosch ARCH=arm64 STAGE=hardened PROVIDER=qemu \
  IMAGE_VERSION=2026-05-06.1 ./scripts/build.sh

./scripts/publish.sh bosch 2026-05-06.1
# publish.sh auto-detects which providers have a .box on disk
# and skips the missing one with a warning, exit 0
```

### 5.3 Auto-detect latest version

If you omit the version, `publish.sh` reads the **latest version directory
that has at least one `.box` file**:

```bash
./scripts/publish.sh bosch                     # uses latest local .box version
./scripts/publish.sh bosch --release           # same, but releases it
```

### 5.4 Publish under a personal account / different org

```bash
VAGRANT_CLOUD_ORG=mydevuser \
  ./scripts/publish.sh bosch 2026-05-06.1
# the box becomes mydevuser/ubuntu2204-cisl1-arm64
```

### 5.5 Different box name

```bash
BOX_NAME=ubuntu2204-cisl1-arm64-test \
  ./scripts/publish.sh bosch 2026-05-06.1
# box tag: bosch/ubuntu2204-cisl1-arm64-test
# expects local files named bosch-ubuntu2204-cisl1-arm64-test-<version>.box
```

If you also want to override the **local** filename, set
`IMAGE_NAME_PREFIX` to match what Packer wrote.

### 5.6 Long-form description

Drop a markdown file at `docs/box-description.md` (or override
`BOX_DESCRIPTION_FILE`). `publish.sh` will pass it via
`--description-file` on `box create` so the box's "Overview" page on
Vagrant Cloud is properly populated.

---

## 6. Re-run, recovery, and idempotency

`publish.sh` uses a `probe`-then-`run` pattern: every create step first
calls the corresponding `vagrant cloud … show` and only attempts to create
when the resource doesn't already exist. **Re-running after a partial
failure is safe.** Concrete behaviors:

| Failure point | What's left behind on Vagrant Cloud | Re-run does |
|---|---|---|
| Network drop during `box create` | Nothing | Re-creates the box |
| Network drop during `version create` | Box exists, version does not | Skips box; creates version |
| Network drop mid-upload | Provider exists with status `pending` or `active` partial | Re-uploads the same `.box` (overwrites) |
| Auth token expired | Whatever existed before | Re-runs from where it left off after you refresh `VAGRANT_CLOUD_TOKEN` |
| Wrong file uploaded by mistake | Provider exists with the wrong content | Re-upload over it; the registry keeps last-write-wins **until released** |

**Once a version is `released`**, providers within it become
**append-only-ish** — you can still upload over a provider, but consumers
who pulled the old hash during the window may get cached results. For
hot-fix-style fixes, prefer **bumping the version** rather than overwriting
in place.

To remove a botched unreleased version entirely:

```bash
vagrant cloud version delete bosch/ubuntu2204-cisl1-arm64 2026-05-06.1
```

This is destructive but acceptable on **unreleased** versions. Don't delete
a released version — it breaks anyone pinned to it.

---

## 7. Troubleshooting matrix

| Symptom | Likely cause | Where to look |
|---|---|---|
| `packer validate` reports "Output directory already exists" | A previous build wrote to the same `IMAGE_VERSION` subdir | Bump the patch (`.1` → `.2`) or `rm -rf` the old subdir if you're sure it's stale |
| Stage 1 hangs at `Waiting for SSH` for > 5 min | autoinstall didn't run — `{{ .HTTPIP }}` mistake, ISO mismatch, or boot_command typo | Watch `qemu-system-aarch64`'s VNC/cocoa output during the run; check `feedback_packer_qemu_user_mode_httpip` |
| Stage 1 produces a tiny qcow2 (< 200 MB) | autoinstall failed silently — installer dropped to a shell, packer waited until SSH timeout | Same as above |
| Stage 2 fails at `ansible-playbook` | Compliance role bug; cross-distro package name divergence; role var schema drift | Run `ansible-playbook` directly against the Stage 1 base outside packer; check `feedback_ansible_*` notes |
| `.box` file produced but `metadata.json` shows wrong provider | qemu source went through stock `vagrant` PP instead of shell-local | Re-read the `bosch-ubuntu2204-arm64-hardened.pkr.hcl` PP block; ensure `only = ["qemu.<source>"]` matches |
| `vagrant box add` fails with "no provider for arch" | `metadata.json` missing the `architecture` field | qemu wrap didn't include it — re-bake; ensure shell-local PP writes `"architecture":"arm64"` |
| `vagrant up --provider qemu` fails immediately | Consumer-side `vagrant-qemu` plugin not installed | `vagrant plugin install vagrant-qemu` |
| `publish.sh` reports "no Vagrant Cloud auth available" | `VAGRANT_CLOUD_TOKEN` not set and `vagrant cloud auth login` not cached | Set the env var or run `vagrant cloud auth login` |
| `publish.sh` exits 3 — missing artifacts | No `.box` files exist for that version | Did Stage 2 finish? Check `ls output/<tenant>/arm64/*/<ver>/*.box` |
| Upload succeeds but `vagrant up` consumer can't find the version | Version is `unreleased` | Run `publish.sh … --release`, OR pin the consumer to a previously released version |
| `vagrant up` pulls the wrong arch | Box version was created without `--no-default-architecture` | Re-create the version with the flag (publish.sh always passes it; only happens when someone uploaded by hand) |
| HCP / Vagrant Cloud auth flow is broken | HashiCorp moved the registry / API endpoint | Check <https://developer.hashicorp.com/vagrant>; the underlying CLI shape doesn't change, only host/token endpoints |

---

## 8. What this runbook is NOT

- **Not a Packer template tutorial.** If you need to add a new tenant or a
  new ansible role, start from the existing `bosch-ubuntu2204-arm64-hardened.pkr.hcl`
  and `BUILD-WORKFLOW.md`, not this doc.
- **Not the x86_64 path.** This is arm64-only. The amd64 (legacy monolith)
  path is documented in the repo `README.md`.
- **Not for self-hosted Vagrant box hosting.** If you want to host the
  `.box` on your own S3/CDN with a hand-written manifest JSON, see
  [`vagrant-cloud-publish.md` § 10](./vagrant-cloud-publish.md#10-self-hosting-alternative).
- **Not a CI/CD setup guide.** Everything above is local-laptop driven.
  Wiring `build.sh` + `publish.sh` into GitHub Actions is a separate task —
  the script API (env vars, exit codes, `--dry-run`, `--release`) is the
  contract a CI workflow would consume.

---

## Appendix — quick command reference

```bash
# Clean from-scratch, both providers, version-tagged today (5 commands):
cd packer

TENANT=bosch ARCH=arm64 STAGE=base     IMAGE_VERSION=$(date +%Y-%m-%d).1 ./scripts/build.sh
TENANT=bosch ARCH=arm64 STAGE=hardened IMAGE_VERSION=$(date +%Y-%m-%d).1 PROVIDER=all ./scripts/build.sh
./scripts/publish.sh bosch $(date +%Y-%m-%d).1 --dry-run
./scripts/publish.sh bosch $(date +%Y-%m-%d).1
# … smoke test …
./scripts/publish.sh bosch $(date +%Y-%m-%d).1 --release
```

Total wall-clock for a from-scratch run: **~20 min**, of which ~12–15 is
Stage 1, ~6 is Stage 2 (both providers), ~2 is publish + release.

Subsequent iterations (Stage 2 only): **~5 min** start to released box.
