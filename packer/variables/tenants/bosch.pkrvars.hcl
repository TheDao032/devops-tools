# Tenant: Bosch — CIS-L1, no FIPS
# Compose with any variables/guest/<guest>-amd64.pkrvars.hcl

tenant             = "bosch"
compliance_profile = "cis-l1"
fips_mode          = "false"

# Banner text — Bosch legal-approved.
login_banner = "BOSCH // Authorized use only. All activity is logged and audited."

# Image name prefix: <tenant>-<compliance>. Final image name is composed by the
# template as: "${image_name_prefix}-${guest_slug}-${image_version}"
# → e.g. "bosch-cisl1-ubuntu2404-2026-07-07.1"
image_name_prefix = "bosch-cisl1"
