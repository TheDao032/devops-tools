#!/bin/bash
# vagrant-qemu `qemu_bin` wrapper (macOS): launch QEMU attached to a socket_vmnet
# shared network so multiple VMs share one L2 segment. vagrant-qemu can't create
# private networks itself and plain QEMU sockets don't carry broadcast/ARP between
# VMs on macOS — socket_vmnet (vmnet.framework) does, without running qemu as root.
#
# All args vagrant-qemu built for qemu are passed through as "$@"; our 2nd NIC in
# the Vagrantfile references the vmnet socket as fd=3 (socket_vmnet_client opens it).
set -euo pipefail

PREFIX="/opt/homebrew"
SOCK="${PREFIX}/var/run/socket_vmnet"
CLIENT="${PREFIX}/opt/socket_vmnet/bin/socket_vmnet_client"

# guest arch follows the same env the Vagrantfile uses (K3S_ARCH), default aarch64
case "${K3S_ARCH:-aarch64}" in
  x86_64|amd64) QSYS="qemu-system-x86_64" ;;
  *)            QSYS="qemu-system-aarch64" ;;
esac
QEMU_BIN="$(command -v "$QSYS" || echo "${PREFIX}/bin/${QSYS}")"

if [ ! -x "$CLIENT" ]; then
  echo "ERROR: socket_vmnet_client not found at $CLIENT" >&2
  echo "  Install:  brew install socket_vmnet" >&2
  exit 1
fi
if [ ! -S "$SOCK" ]; then
  echo "ERROR: socket_vmnet daemon socket not found at $SOCK" >&2
  echo "  Start:  sudo brew services start socket_vmnet" >&2
  exit 1
fi

exec "$CLIENT" "$SOCK" "$QEMU_BIN" "$@"
