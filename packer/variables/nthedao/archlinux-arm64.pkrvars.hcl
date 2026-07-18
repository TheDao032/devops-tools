# archlinux (nthedao personal line) — STAGE 2 variables.
# Pairs with: templates/nthedao/archlinux-arm64.pkr.hcl
#
# STAGE 1 (the ALARM tarball bootstrap) is configured in scripts/archlinux/base.env,
# NOT here — stage 1 is a shell bootstrap, not a Packer build (Arch aarch64 has no
# installer ISO). This file only drives the stage-2 Packer box build.
#
# Use case: lightweight personal k3s-etcd lab box on Apple Silicon — the fast,
# small alternative to the Ubuntu lines. Intended to publish as
# nthedao2705/archlinux-arm64 and (optionally) be consumed by
# vagrant/vagrant-files/k3s/config.yaml.

# Output tree slug: output/archlinux/arm64/<provider>/<version>/...
tenant = "archlinux"

# Bootstrap user baked by stage 1 (has NOPASSWD sudo + the packer key). Packer
# SSHes in as this user; the box ships with it as the vagrant login.
ssh_username = "packer"

# Box/image name. Version goes in the directory; the artifact keeps a stable
# prefix so `latest` symlinks are simple. Matches the intended Vagrant Cloud/HCP
# box name nthedao2705/archlinux-arm64.
image_name_prefix = "archlinux-arm64"

# Extra pacman packages to bake in (space-separated). Kept empty for a minimal
# base; add e.g. "docker containerd" or k3s prereqs when the lab needs them.
extra_packages = ""
