# Guest: RHEL 9 — amd64
# Paired with: templates/_base/rhel-amd64.pkr.hcl
#
# NOTE: RHEL ISOs are gated behind Red Hat subscription. This filename assumes
# the ISO has been downloaded to the machine-local iso_cache_prefix. Point
# iso_url via an internal mirror URL if you don't cache DVDs locally — but then
# override iso_cache_prefix to a blank string and set a full iso_filename URL.

iso_filename = "rhel-9.4-x86_64-dvd.iso"
# Set to a real sha256 before any production build. `none` lets `packer validate`
# pass structurally; packer emits a loud warning at build time. NEVER prod-bake with `none`.
iso_checksum = "none"
guest_slug   = "rhel9"

ssh_username = "packer"
