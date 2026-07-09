# Tenant: Renesas — CIS-L2 + FIPS 140-3
# Compose with variables/guest/rhel<N>-amd64.pkrvars.hcl
#
# RHEL subscription credentials must NOT be hardcoded. Set at build time:
#   export RHEL_USERNAME=... RHEL_PASSWORD=...

tenant             = "renesas"
compliance_profile = "cis-l2"
fips_mode          = "true"

# Banner text — Renesas legal-approved.
login_banner = "RENESAS // Authorized use only. All activity is logged and audited."

# Composed image name: e.g. "renesas-cisl2-fips-rhel9-2026-07-07.1"
image_name_prefix = "renesas-cisl2-fips"

# Optional: subscription pool ID passthrough (currently unused by the template).
rhel_subscription_pool_id = ""
