# Publishing the bosch hardened arm64 box to Vagrant Cloud

This document covers shipping the Path D deliverables (`*.box` files produced by
`packer/templates/bosch-ubuntu2204-arm64-hardened.pkr.hcl`) to the public
HashiCorp Vagrant Cloud registry (`app.vagrantup.com`) for both the
`virtualbox` and `qemu` providers, on the `arm64` architecture, for engineers
running Apple Silicon.

> **Caveat — registry naming.** HashiCorp's hosted Vagrant box registry has
> historically been called *Vagrant Cloud* at `app.vagrantup.com`. After the
> IBM acquisition (April 2024) the product line is being rolled into HCP
> branding. The hostname `app.vagrantup.com` is still the canonical box
> registry endpoint and the `vagrant cloud …` CLI subcommand still drives it.
> If the URL has moved by the time you read this, the workflow below is
> identical against the new host — only the auth endpoint and dashboard URL
> change. Verify the current status of `app.vagrantup.com` before publishing
> credentials.

---

## 1. The box landscape today

```
output/bosch/arm64/
├── virtualbox/2026-05-05.1/
│   ├── bosch-ubuntu2204-cisl1-arm64-2026-05-05.1.box   ← ready to publish
│   ├── bosch-ubuntu2204-cisl1-arm64-2026-05-05.1.ova
│   └── manifest.json
└── qemu/2026-05-05.1/
    ├── bosch-ubuntu2204-cisl1-arm64-2026-05-05.1.qcow2 ← needs to be wrapped (see §2)
    ├── efivars.fd
    └── manifest.json
```

The virtualbox path runs the stock Packer `vagrant` post-processor (which
emits a `provider=virtualbox` `.box`). The qemu path stops at `qcow2` because
Packer's stock `vagrant` PP does not natively support a `qemu` provider —
its supported list is `virtualbox`, `vmware`, `hyperv`, `libvirt`,
`parallels`, `docker`. To ship a `provider=qemu` box for the
`vagrant-qemu` consumer plugin (or `vagrant_utm` for UTM-on-macOS), we have
to assemble the `.box` archive ourselves.

---

## 2. Producing a `provider=qemu` `.box` from the qcow2

A Vagrant box is a `tar.gz` (renamed `.box`) containing **at minimum**:

```
box.tar.gz/
├── metadata.json    {"provider": "qemu"}                       ← REQUIRED
├── Vagrantfile      Provider-specific defaults (RAM, CPUs, …)  ← optional but expected
└── <disk image>     The qcow2 (filename can vary)               ← REQUIRED
```

Add a `shell-local` post-processor to the qemu chain in
`templates/bosch-ubuntu2204-arm64-hardened.pkr.hcl`:

```hcl
post-processor "shell-local" {
  only            = ["qemu.bosch-ubuntu2204-arm64"]
  inline_shebang  = "/bin/bash -euo pipefail"
  environment_vars = [
    "OUTPUT_DIR=${local.output_dir_qemu}",
    "BOX_NAME=${var.image_name_prefix}-${var.image_version}.box",
    "QCOW2=${var.image_name_prefix}-${var.image_version}.qcow2",
  ]
  inline = [
    "set -x",
    "cd \"$OUTPUT_DIR\"",
    "stage=$(mktemp -d)",
    "trap 'rm -rf \"$stage\"' EXIT",
    "cp \"$QCOW2\" \"$stage/box.img\"",
    "cat > \"$stage/metadata.json\" <<'JSON'",
    "{\"provider\":\"qemu\",\"format\":\"qcow2\",\"architecture\":\"arm64\"}",
    "JSON",
    "cat > \"$stage/Vagrantfile\" <<'RUBY'",
    "Vagrant.configure('2') do |config|",
    "  config.vm.provider :qemu do |qe|",
    "    qe.arch         = 'aarch64'",
    "    qe.machine      = 'virt,accel=hvf,highmem=on'",
    "    qe.cpu          = 'host'",
    "    qe.smp          = 'cpus=2,sockets=1,cores=2,threads=1'",
    "    qe.memory       = '2048'",
    "    qe.net_device   = 'virtio-net-device'",
    "    qe.ssh_port     = 50022",
    "  end",
    "end",
    "RUBY",
    "tar -czf \"$BOX_NAME\" -C \"$stage\" metadata.json Vagrantfile box.img",
    "ls -lh \"$BOX_NAME\"",
  ]
}
```

Notes:
- `qe.machine = 'virt,accel=hvf,highmem=on'` is the Apple Silicon
  hypervisor-framework path. Drop `accel=hvf` if you ever bake for a
  Linux/x86 host — `vagrant-qemu` will pick `tcg` and run slow.
- `qe.cpu = 'host'` is correct *only* on the same chip family as the bake
  host. For a portable cross-tenant box, use `qe.cpu = 'max'`.
- The Vagrantfile inside the box is a **default** that consumers can
  override. Don't put tenant-specific settings here.

After this change, `STAGE=hardened ARCH=arm64 ./scripts/build.sh bosch qemu`
will produce:

```
output/bosch/arm64/qemu/<version>/bosch-ubuntu2204-cisl1-arm64-<version>.box
```

---

## 3. Architecture awareness — non-negotiable for arm64 boxes

Vagrant 2.4.0 introduced multi-arch box support. The boxes you produced are
**arm64-only** (you bake on Apple Silicon, run on Apple Silicon). Without
declaring this, Vagrant Cloud will hand the box to x86_64 consumers and
`vagrant up` will fail at boot.

Every publish step below uses:

```
--architecture arm64
--no-default-architecture     # do NOT make arm64 the architecture-fallback
```

When you eventually ship an `amd64` build (cloud/CI host), publish a second
provider entry on the *same* version with `--architecture amd64`. Vagrant
selects the matching arch at `vagrant up` time.

---

## 4. Authentication

Generate a token at <https://app.vagrantup.com/account/security> (Web UI:
*Account → Security → API tokens → Generate token*). Scope: write to your
boxes only — do **not** generate a token with admin scope for a CI runner.

Store it once with the CLI:

```bash
vagrant cloud auth login
# Pastes token into ~/.vagrant.d/data/vagrant_login_token
```

Or via env for CI (preferred — token rotates without rewriting state files):

```bash
export VAGRANT_CLOUD_TOKEN="atlasv1.…"
```

> **Never** commit a token to git. Store it in your secrets manager
> (1Password / AWS Secrets Manager / Vault) and inject at CI time.

---

## 5. Path A — Publish via CLI

The CLI has two flavors: a one-shot `publish` (good for ad-hoc) and the
underlying granular commands (good for CI, where you want each step to
be re-runnable on failure).

### 5.1. One-shot — `vagrant cloud publish`

```bash
# Variables once
ORG="bosch"                                  # your Vagrant Cloud org/user
BOX="ubuntu2204-cisl1-arm64"                 # box name (org/box appears in URLs)
VER="2026-05-05.1"
VBOX_FILE="output/bosch/arm64/virtualbox/${VER}/bosch-ubuntu2204-cisl1-arm64-${VER}.box"
QEMU_FILE="output/bosch/arm64/qemu/${VER}/bosch-ubuntu2204-cisl1-arm64-${VER}.box"

# 1) virtualbox + arm64 — creates box, version, provider, uploads, releases
vagrant cloud publish "${ORG}/${BOX}" "${VER}" virtualbox \
  --architecture arm64 \
  --no-default-architecture \
  --release \
  --short-description "Ubuntu 22.04 ARM64, CIS Level 1 hardened, bosch tenant" \
  --description-from-file docs/box-description.md \
  --version-description "Build ${VER} — ${BUILD_DATE:-$(date +%F)}" \
  "${VBOX_FILE}"

# 2) qemu + arm64 — adds a second provider to the SAME version
#    Use --no-release on the first call if you want both providers attached
#    before going public; rerun with --release when both are uploaded.
vagrant cloud publish "${ORG}/${BOX}" "${VER}" qemu \
  --architecture arm64 \
  --no-default-architecture \
  --release \
  "${QEMU_FILE}"
```

`vagrant cloud publish` is idempotent on box/version: if `${ORG}/${BOX}`
already exists with version `${VER}`, it adds the provider rather than
recreating. Watch for "version already released" warnings — once a version
is released you cannot upload a new provider to it; cut a new version
(`2026-05-05.2`) instead.

### 5.2. Granular — for CI pipelines that need re-runnable stages

```bash
# 1) Create the box (idempotent — 422 if exists, ignore)
vagrant cloud box create "${ORG}/${BOX}" \
  --short-description "Ubuntu 22.04 ARM64, CIS Level 1 hardened, bosch tenant" \
  --description-from-file docs/box-description.md \
  --private  # remove if you want it public

# 2) Create the version
vagrant cloud version create "${ORG}/${BOX}" "${VER}" \
  --description "Build ${VER}"

# 3) Create each provider entry
vagrant cloud provider create "${ORG}/${BOX}" virtualbox "${VER}" \
  --architecture arm64 --no-default-architecture
vagrant cloud provider create "${ORG}/${BOX}" qemu "${VER}" \
  --architecture arm64 --no-default-architecture

# 4) Upload the box files
vagrant cloud provider upload "${ORG}/${BOX}" virtualbox "${VER}" "${VBOX_FILE}" \
  --architecture arm64
vagrant cloud provider upload "${ORG}/${BOX}" qemu "${VER}" "${QEMU_FILE}" \
  --architecture arm64

# 5) Release the version (this is what makes it appear to consumers)
vagrant cloud version release "${ORG}/${BOX}" "${VER}"
```

Each step exits non-zero on failure, so wrap in `set -e` in CI. Consider
guarding the create steps with a probe (`vagrant cloud box show …`) so
re-runs are clean.

### 5.3. Auto-publish from Packer (`vagrant-cloud` post-processor)

If you want zero-touch publishing on every successful build, chain the
`vagrant-cloud` PP after the `vagrant` PP:

```hcl
post-processors {                          // double-brace = chained
  post-processor "vagrant" {
    only                = ["virtualbox-ovf.bosch-ubuntu2204-arm64"]
    output              = "${local.output_dir_virtualbox}/${var.image_name_prefix}-${var.image_version}.box"
    keep_input_artifact = true
    compression_level   = 6
  }
  post-processor "vagrant-cloud" {
    box_tag             = "bosch/ubuntu2204-cisl1-arm64"
    version             = var.image_version
    architecture        = "arm64"
    no_release          = false   // true = upload only, release manually later
    access_token        = "${env("VAGRANT_CLOUD_TOKEN")}"
  }
}
```

**Trade-off:** auto-publish couples build success to registry writes. A
flaky network breaks the build. CI-friendly pattern is to *not* chain —
build artefact locally, run `vagrant cloud publish` as a separate stage.

---

## 6. Path B — Publish via Web UI (`app.vagrantup.com`)

For one-off publishes or when teaching another engineer the model.

### 6.1. First-time setup (per box)

1. Navigate to <https://app.vagrantup.com/>
2. Sign in (or sign up — your username becomes your default org).
3. *Top right → New Vagrant Box*. Form:
   - **Name:** `ubuntu2204-cisl1-arm64`  *(box-only; org is implied)*
   - **Visibility:** *Private* (recommended for tenant boxes; flip to
     *Public* only if the build is genuinely shareable)
   - **Short description:** "Ubuntu 22.04 ARM64, CIS Level 1 hardened,
     bosch tenant"
   - **Description (markdown):** dump the contents of
     `docs/box-description.md` here. This is the page consumers land on.
4. *Create box.*

You now have an empty box at `https://app.vagrantup.com/<org>/boxes/ubuntu2204-cisl1-arm64`.

### 6.2. Adding a version (per build)

1. Open the box page.
2. *New version* (top-right of the version list).
3. Fill:
   - **Version:** `2026-05-05.1` *(must match `var.image_version` — the
     manifest stamp inside the box)*
   - **Description (markdown):** changelog notes. Reference any
     [[40-decisions/…]] ADRs that justify the build.
4. *Create version.* It lands in **unreleased** state — invisible to
   `vagrant box add`/`vagrant up`.

### 6.3. Adding providers (per provider × architecture)

You need this twice for an arm64-only build (virtualbox + qemu), four times
for a multi-arch shipment (× amd64).

1. Inside the unreleased version, *New provider*:
   - **Provider:** `virtualbox`  *(or `qemu`)*
   - **Architecture:** `arm64`
   - **Default architecture:** **off** *(critical — see §3)*
   - **Hosting:** *Self-managed* (URL) **OR** *Vagrant Cloud-hosted*
     (file upload). Use Vagrant Cloud-hosted unless you're parking the
     `.box` in your own S3/Artifactory.
2. *Create provider.*
3. Drag-and-drop the `.box` file. Watch the upload bar — boxes here are
   1.5 GB, expect 5–15 min on a typical home connection.
4. Repeat for the second provider.

### 6.4. Releasing the version

Once both providers are 100% uploaded:

1. Back to the version page.
2. *Release version* (the prominent green button).
3. Confirm.

The version is now live. `vagrant box add bosch/ubuntu2204-cisl1-arm64`
on any consumer machine (with the right plugins installed) will fetch it.

> **Once released, a version is mostly immutable.** You can edit the
> description; you cannot add new providers, replace box files, or
> un-release. To fix a bad release, *Revoke* the version (consumers stop
> getting it on `vagrant box update`) and cut a new version with the fix.

---

## 7. Consumer-side smoke test (do this before announcing the box)

```bash
# On a different Apple Silicon Mac if possible — or at least a fresh dir
mkdir ~/tmp/box-smoke && cd ~/tmp/box-smoke

# vagrant-qemu plugin is required for the qemu provider
vagrant plugin install vagrant-qemu

# Init + up via virtualbox
vagrant init bosch/ubuntu2204-cisl1-arm64
vagrant up --provider virtualbox
vagrant ssh -c "cat /etc/image-metadata && sudo aa-status | head -3"
vagrant destroy -f

# Init + up via qemu
vagrant up --provider qemu
vagrant ssh -c "cat /etc/image-metadata"
vagrant destroy -f
```

Both paths must succeed before flipping the box to *Public* or pointing
engineers at it.

---

## 8. Recommended automation pattern

```
┌──────────────────────────────────────────────────────────────┐
│  packer/scripts/build.sh                                     │
│  └─ packer build → output/.../$NAME-$VER.box (per provider)  │
└─────────────────────┬────────────────────────────────────────┘
                      ▼
┌──────────────────────────────────────────────────────────────┐
│  packer/scripts/publish.sh   (NEW — wrap §5.2)               │
│  ├─ box create   (ignore-422)                                │
│  ├─ version create                                           │
│  ├─ provider create × arch                                   │
│  ├─ provider upload × arch                                   │
│  └─ version release                                          │
└─────────────────────┬────────────────────────────────────────┘
                      ▼
┌──────────────────────────────────────────────────────────────┐
│  GitHub Actions / GitLab CI                                  │
│  ├─ stage: bake          → produce .box                      │
│  ├─ stage: smoke         → vagrant up + assert metadata      │
│  ├─ stage: publish       → publish.sh (manual approval gate) │
│  └─ stage: notify        → Slack / email engineers           │
└──────────────────────────────────────────────────────────────┘
```

**Don't** auto-release on every build. Gate the *release* step on a
human approval (GitHub environment protection, GitLab manual job).
The bake → upload steps can be fully automated; *making it visible to
consumers* is a deliberate publish event.

---

## 9. Common failure modes

| Symptom | Cause | Fix |
|---|---|---|
| `vagrant up` on x86 host pulls arm64 box, fails at boot | `--no-default-architecture` was forgotten | Re-publish with arch flag set; clear consumer cache (`vagrant box remove …`) |
| `vagrant cloud publish` hangs at upload | Token doesn't have write scope, or hit free-tier 1 GB limit | Regenerate token with full scope; if free tier, switch to private OSS plan or self-host |
| `provider create … 422` | Provider already exists at that arch on that version | Use `vagrant cloud provider update` or upload via existing entry |
| `version release` errors "no providers" | Forgot to upload the `.box`; provider entry exists but file slot is empty | Upload first, then release |
| Consumer pulls box but `vagrant up --provider qemu` errors `unknown provider` | Consumer didn't `vagrant plugin install vagrant-qemu` | Document in the box's *Description* field |
| `tar: Cannot stat: No such file or directory` from §2 shell-local | qcow2 path expanded wrong (Packer didn't see staged artifact yet) | Confirm the `shell-local` PP runs after the qemu source's manifest PP, not in parallel |

---

## 10. Self-hosting alternative (no Vagrant Cloud)

If `app.vagrantup.com` becomes untenable (HCP migration friction, billing,
private box requirement), the same `.box` files can be served from any
HTTPS endpoint. Vagrant fetches a metadata JSON and pulls the `.box` URL
from it:

```json
{
  "name": "bosch/ubuntu2204-cisl1-arm64",
  "description": "CIS-L1 hardened Ubuntu 22.04 ARM64, bosch tenant",
  "versions": [
    {
      "version": "2026-05-05.1",
      "providers": [
        {
          "name": "virtualbox",
          "architecture": "arm64",
          "default_architecture": false,
          "url": "https://boxes.bosch.example/ubuntu2204-cisl1-arm64/2026-05-05.1/virtualbox-arm64.box",
          "checksum_type": "sha256",
          "checksum": "<sha256>"
        },
        {
          "name": "qemu",
          "architecture": "arm64",
          "default_architecture": false,
          "url": "https://boxes.bosch.example/ubuntu2204-cisl1-arm64/2026-05-05.1/qemu-arm64.box",
          "checksum_type": "sha256",
          "checksum": "<sha256>"
        }
      ]
    }
  ]
}
```

Park `.box` files + this metadata in S3 (or any static webserver) and
consumers run `vagrant box add https://boxes.bosch.example/ubuntu2204-cisl1-arm64/metadata.json`.
This is the path I'd recommend if any of the boxes are sensitive enough
that a hosted public registry is the wrong tenancy model.

---

## 11. Summary checklist

Before you click *Release* / run `vagrant cloud version release`:

- [ ] `var.image_version` matches the Vagrant Cloud version string exactly
- [ ] Both providers (virtualbox, qemu) attached to the version
- [ ] `architecture = arm64` set on every provider entry
- [ ] `default_architecture = false` set (to prevent x86 hosts grabbing arm64)
- [ ] Smoke test passed on a clean Apple Silicon Mac for **both** providers
- [ ] Box description includes the consumer-side `vagrant plugin install vagrant-qemu` requirement
- [ ] Token used for publish is org-scoped, not personal-admin
- [ ] Manifest inside the image (`/etc/image-metadata`) matches the version
- [ ] If private: ACL'd to only the engineering org/team

Once green, release the version and post the consumer command in your
team's onboarding doc:

```bash
vagrant init bosch/ubuntu2204-cisl1-arm64
vagrant up --provider virtualbox   # or --provider qemu
```
