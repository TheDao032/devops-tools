# providers/vmware_fusion/vmware_fusion.rb
#
# Base class for VMware Fusion VM definitions. Subclassed by per-OS provider
# files (ubuntu.rb, rhel.rb) which override `provision_vm`.
#
# Constructor argument order matches the call site in
# infrastructure/vagrant_plan_applier.rb#build_vm (vmware_fusion branch):
#   box, config, name, hostname, ip, network_mode, ports, provisioning_files,
#   memory, cpus

require_relative "../vm"

class VMWareFusionVM < VM
  attr_accessor :box, :memory, :cpus, :provider_name

  def initialize(
    box,
    config,
    name,
    hostname,
    ip,
    network_mode,
    ports = [],
    provisioning_files = [],
    memory = 1024,
    cpus = 1
  )
    super(config, name, hostname, ip, network_mode, ports, provisioning_files)
    @box      = box
    @memory   = memory
    @cpus     = cpus
    @provider = "vmware_fusion"
  end

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

  def provider(node)
    node.vm.provider @provider do |v|
      v.vmx["displayname"] = @name
      v.vmx["memsize"]     = @memory.to_s
      v.vmx["numvcpus"]    = @cpus.to_s
      v.gui                = false
    end
  end

  def provision_vm(_node, _os, _ip_nw, _machines, _os_system_info)
    # noop in base
  end
end
