# virtualbox.rb
require_relative '../vm'
require_relative '../../utils/utils'

class VirtualBoxVM < VM
  attr_accessor :memory, :cpu, :disk_size, :vbox_guest_path, :box
  include Utils

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
    disk_size = 30
  )
    super(config, name, hostname, ip, network_mode, ports, provisioning_files)
    @box = box
    @memory = memory
    @cpus = cpus
    @disk_size = disk_size
    @vbox_guest_path = vbox_guest_path
    @provider = "virtualbox"
  end

  def provider(node)
    raise NotImplementedError, "Subclasses must implement the define method"
  end

  # Runs provisioning steps that are required by masters and slaves
  def provision_vm(node, os, ip_nw, machines, os_system_info)
    raise NotImplementedError, "Subclasses must implement the define method"
  end

  def config_network(node)
    # raise NotImplementedError, "Subclasses must implement the define method"
    if @network_mode == 'BRIDGE'
      public_network(node)
    else
      private_network(node)
    end
  end

  def public_network(node)
    node.vm.network :public_network, type: "dhcp", bridge: get_bridge_adapter(@provider)
  end

  def private_network(node)
    node.vm.network :private_network, ip: @ip
    forward_ports(node)
  end

  def define(
    os,
    ip_nw,
    machines,
    os_system_info
  )
    @config.vm.define @name do |node|
      node.vm.box = @box
      provider(node)

      node.vm.hostname = @hostname
      config_network(node)
      provision_vm(node, os, ip_nw, machines, os_system_info)
      provision_files(node)
    end
  end
end
