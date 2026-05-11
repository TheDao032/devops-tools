# providers/virtualbox/virtualbox.rb
#
# Base class for VirtualBox VM definitions. Subclassed by per-OS provider
# files (ubuntu.rb, centos.rb, rhel.rb) which override `provision_vm` to add
# OS-specific shell provisioning steps.
#
# Constructor argument order matches the call site in
# infrastructure/vagrant_plan_applier.rb#build_vm:
#   box, config, name, hostname, ip, network_mode, vbox_guest_path,
#   ports, provisioning_files, memory, cpus[, disk_size]

require_relative "../vm"

class VirtualBoxVM < VM
  attr_accessor :box, :memory, :cpus, :disk_size, :vbox_guest_path, :provider_name

  def initialize(
    box,
    config,
    name,
    hostname,
    ip,
    network_mode,
    vbox_guest_path,
    ports = [],
    provisioning_files = [],
    memory = 1024,
    cpus = 1,
    disk_size = 10
  )
    super(config, name, hostname, ip, network_mode, ports, provisioning_files)
    @box             = box
    @vbox_guest_path = vbox_guest_path
    @memory          = memory
    @cpus            = cpus
    @disk_size       = disk_size
    @provider        = "virtualbox"
  end

  # Entry point invoked by VagrantPlanApplier#define_machine.
  def define(os, ip_nw, machines, os_system_info)
    @config.vm.define @name do |node|
      node.vm.box      = @box if @box && !@box.empty?
      node.vm.hostname = @hostname

      config_network(node, @network_mode)
      forward_ports(node)
      provision_files(node)
      provider(node)

      provision_vm(node, os, ip_nw, machines, os_system_info)
    end
  end

  def config_network(node, network_mode)
    if network_mode == "BRIDGE"
      public_network(node)
    else
      private_network(node)
    end
  end

  def public_network(node)
    node.vm.network "public_network", ip: @ip, type: "dhcp"
  end

  def private_network(node)
    node.vm.network "private_network", ip: @ip
  end

  # VirtualBox-specific provider config. Subclasses MAY override to add
  # vboxmanage customizations (extra disks, NIC tuning, etc.).
  def provider(node)
    node.vm.provider @provider do |v|
      v.name   = @name
      v.memory = @memory
      v.cpus   = @cpus
    end
  end

  # Default no-op. Per-OS subclasses override with shell provisioner steps
  # (setup-hosts, setup-dns, setup-ssh, etc.) — see virtualbox/ubuntu.rb.
  def provision_vm(_node, _os, _ip_nw, _machines, _os_system_info)
    # noop in base class
  end
end
