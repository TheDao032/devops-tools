set -e

PROVIDER="virtualbox"
VBOX_GUEST_DISK="/Applications/VirtualBox.app/Contents/MacOS/VBoxGuestAdditions_7.0.20.iso"
NETWORK_MODE="NAT"

VM_NAME=${1:-""}
VAGRANT_ACTION=${2}

# shift 1
#
# ARGS="$@"

if [[ -z "${VAGRANT_ACTION}" ]]; then
  exit 1
fi

if [[ -z "${VM_NAME}" ]]; then
  cd vagrant && VAGRANT_VAGRANTFILE=vagrant-files/kubernetes/k3s.Vagrantfile vagrant ${VAGRANT_ACTION}
else
  cd vagrant && VAGRANT_VAGRANTFILE=vagrant-files/kubernetes/k3s.Vagrantfile vagrant ${VAGRANT_ACTION} ${VM_NAME}
fi

exit 0
