# Bosch-specific variables.
# Pairs with: templates/bosch-ubuntu2204-hardened.pkr.hcl
#
# Compliance: CIS-L1 (no FIPS — Bosch deployment doesn't require it).

tenant              = "bosch"
compliance_profile  = "cis-l1"
fips_mode           = "false"

# Ubuntu 22.04.5 LTS server, served from the local ISO cache.
# 22.04.4 was rotated off the public mirrors when 22.04.5 shipped.
# To refresh: download from any Ubuntu mirror, verify against the canonical
# SHA256SUMS at https://releases.ubuntu.com/22.04/SHA256SUMS, then update
# both iso_url and iso_checksum below. The hash is identical across mirrors.
iso_url      = "file:///Users/thedao/iso-cache/ubuntu-22.04.5-live-server-amd64.iso"
iso_checksum = "sha256:9bc6028870aef3f74f4e16b900008179e78b130e6b0b9a140635434a46aa98b0"

# Default bootstrap user.
ssh_username = "packer"

# Banner text — Bosch legal-approved.
login_banner = "BOSCH // Authorized use only. All activity is logged and audited."

# Output box name pattern.
image_name_prefix = "bosch-ubuntu2204-cisl1"
