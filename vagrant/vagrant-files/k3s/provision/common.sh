#!/usr/bin/env bash
# Lab networking plumbing for every node: bring up the vmnet cluster NIC with a
# static IP and write /etc/hosts. This is vagrant-qemu/socket_vmnet-specific and
# must run before Ansible (which pins flannel to k3scl0). Kernel prereqs, k3s,
# etcd and HAProxy are all handled by the Ansible roles (roles/k3s-etcd/*).
# Runs as root (Vagrant privileged shell).
set -euo pipefail

SUBNET="$1"      # e.g. 192.168.56
NODE_MAC="$2"    # MAC of the 2nd (cluster) NIC, e.g. 52:54:00:ab:cd:11
NODE_IP="$3"     # e.g. 192.168.56.11
NODE_NAME="$4"

NODE_MAC_LC="$(echo "$NODE_MAC" | tr 'A-Z' 'a-z')"

echo "[common] ${NODE_NAME}: locating cluster NIC by MAC ${NODE_MAC_LC}"
CUR=""
for ifc in $(ls /sys/class/net); do
  [ "$ifc" = "lo" ] && continue
  if [ "$(cat /sys/class/net/$ifc/address 2>/dev/null)" = "$NODE_MAC_LC" ]; then
    CUR="$ifc"; break
  fi
done
[ -n "$CUR" ] || { echo "[common] FATAL: no NIC with MAC ${NODE_MAC_LC}"; ip -o link; exit 1; }
echo "[common] cluster NIC is currently '${CUR}'"

# Down it first so netplan can rename it live (set-name on a busy iface fails).
ip link set "$CUR" down 2>/dev/null || true

# Rename to a stable name (k3scl0) + assign static IP. Matching by MAC + set-name
# means the box's primary netplan (match en*/driver virtio_net) won't grab this NIC.
cat >/etc/netplan/99-k3s-cluster.yaml <<EOF
network:
  version: 2
  ethernets:
    k3scl0:
      match:
        macaddress: "${NODE_MAC_LC}"
      set-name: k3scl0
      addresses: [${NODE_IP}/24]
      dhcp4: false
      dhcp6: false
EOF
chmod 600 /etc/netplan/99-k3s-cluster.yaml
netplan apply || true
sleep 2

if ip link show k3scl0 >/dev/null 2>&1; then
  IFACE="k3scl0"
else
  # Rename didn't take (rare) — configure the current name directly so the node is still reachable.
  echo "[common] set-name rename didn't apply; configuring ${CUR} directly"
  IFACE="$CUR"
  ip addr flush dev "$IFACE" 2>/dev/null || true
  ip addr add "${NODE_IP}/24" dev "$IFACE"
  ip link set "$IFACE" up
fi
echo "[common] cluster iface=${IFACE} ip=${NODE_IP}"

# Static /etc/hosts for the whole cluster (no DNS in the lab)
sed -i '/k3s-lb\|k3s-server-\|k3s-agent-/d' /etc/hosts
cat >>/etc/hosts <<EOF
${SUBNET}.10 k3s-lb
${SUBNET}.11 k3s-server-1
${SUBNET}.12 k3s-server-2
${SUBNET}.21 k3s-agent-1
${SUBNET}.22 k3s-agent-2
EOF

echo "[common] ${NODE_NAME} network ready (Ansible handles prereqs + k3s)"
