# Shared variable defaults for all tenant builds.
# Tenant-specific files (renesas.pkrvars.hcl, bosch.pkrvars.hcl) override.
#
# Pass to packer with -var-file:
#   packer build -var-file=variables/common.pkrvars.hcl \
#                -var-file=variables/renesas.pkrvars.hcl \
#                templates/renesas-rhel9-hardened.pkr.hcl

# Output base directory. Tenant + provider + version are appended.
output_base_dir = "output"

# Version stamp written into /etc/image-metadata.
# Override per build: -var image_version=2026-05-01.3
image_version = "dev"

# SSH timeout for cloud-init / kickstart phases. RHEL kickstart can be slow.
ssh_timeout = "45m"

# CPU/memory for the build VM. Generous so the bake doesn't drag.
build_cpus   = 4
build_memory = 4096

# Disk size in MB. Big enough for OS + auditd logs + package cache headroom.
disk_size_mb = 20480
