# Default Vagrantfile shipped INSIDE the qemu .box for vagrant-qemu consumers.
#
# vagrant-qemu plugin: https://github.com/ppggff/vagrant-qemu
#
# These values are sane defaults for an Apple Silicon (M-series) Mac running
# Homebrew qemu via the Hypervisor.framework accelerator. Consumers can
# override any of them in their own Vagrantfile (the user's Vagrantfile
# always wins over the box's bundled one).
#
# IMPORTANT — `qe.cpu = 'host'` only works when the consumer's chip family
# matches the bake-time chip family. For maximum portability across Apple
# Silicon generations (M1/M2/M3/M4), `qe.cpu = 'max'` is safer at a small
# perf cost; switch if you hit "unsupported feature" errors on consumer
# Macs. For the bosch fleet we standardize on M-series + 'host' for now.

Vagrant.configure('2') do |config|
  config.vm.provider :qemu do |qe|
    qe.arch         = 'aarch64'
    qe.machine      = 'virt,accel=hvf,highmem=on'
    qe.cpu          = 'host'
    qe.smp          = 'cpus=2,sockets=1,cores=2,threads=1'
    qe.memory       = '2048'
    # `virtio-net-pci` (NOT `virtio-net-device`). On aarch64 virt machines,
    # `virtio-net-device` uses virtio-mmio → guest NIC is named `eth0` →
    # netplan's `match: name: en*` ignores it → DHCP never runs → no
    # external network. `virtio-net-pci` puts the NIC on PCIe → predictable
    # `enpXsY` name → netplan matches → DHCP → vagrant ssh works.
    # The bake-time Packer template uses `-device virtio-net` (PCI default
    # on aarch64), so this also keeps consumer parity with the bake.
    qe.net_device   = 'virtio-net-pci'
    qe.ssh_port     = 50022
  end

  # SSH user contract — matches the bake's cloud-init user.
  config.ssh.username = 'packer'
  # The private key lives in the consumer's Vagrant state; the public half
  # was injected at bake time. Consumers replacing the keypair must re-bake
  # (or run cloud-init again at first boot — out of scope for this default).
end
