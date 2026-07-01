#!/usr/bin/env bash
# Generate ssh.config for this inventory from the running vagrant-qemu VMs.
# vagrant-qemu forwards each VM's SSH to 127.0.0.1:5001x with a per-VM key;
# `vagrant ssh-config` emits Host entries (k3s-lb, k3s-server-1, ...) that match
# the inventory hostnames, so Ansible connects via `-F ssh.config`.
set -euo pipefail

VAGRANT_DIR="${1:-$HOME/Projects/Infrastrutures/devops-tools/vagrant/vagrant-files/k3s}"
OUT="$(cd "$(dirname "$0")" && pwd)/ssh.config"

if [ ! -f "${VAGRANT_DIR}/Vagrantfile" ]; then
  echo "ERROR: no Vagrantfile at ${VAGRANT_DIR}" >&2
  echo "Pass the k3s vagrant dir as arg 1." >&2
  exit 1
fi

( cd "${VAGRANT_DIR}" && vagrant ssh-config ) > "${OUT}"
echo "Wrote ${OUT}"
# NOTE: point -i at inventory.yml (the file), NOT the dir — else Ansible tries to
# parse this .sh as an inventory source. group_vars still load from ./group_vars/.
echo "Now run:  ansible-playbook -i inventory.yml ../../../../playbooks/k3s-etcd-playbooks/site.yml"
