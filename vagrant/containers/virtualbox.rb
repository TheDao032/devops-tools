# virtualbox.rb
require_relative 'vm'
require_relative '../utils/utils'

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
    disk_size = 10
  )
    super(config, name, hostname, ip, network_mode, ports, provisioning_files)
    @box = box
    @memory = memory
    @cpus = cpus
    @disk_size = disk_size
    @vbox_guest_path = vbox_guest_path
    @network_mode = network_mode
    @provider = "virtualbox"
  end

  def provider(node)
    node.vm.provider "virtualbox" do |vb|
      vb.name = @name
      vb.memory = @memory
      vb.cpus = @cpus
      vb.customize ["storageattach", :id, "--storagectl", "IDE", "--port", 1, "--device", 0, "--type", "dvddrive", "--medium", @vbox_guest_path]
      # vb.customize ["createhd", "--filename", "#{@name}.vdi", "--size", @disk_size * 1024]
      # vb.customize ["storagectl", :id, "--name", "SATA Controller", "--add", "sata", "--controller", "IntelAHCI"]
      # vb.customize ["storageattach", :id, "--storagectl", "SATA Controller", "--port", 0, "--device", 0, "--type", "hdd", "--medium", "#{@name}.vdi"]
    end
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

  # Runs provisioning steps that are required by masters and slaves
  def provision_vm(
    node,
    os,
    ip_nw,
    machines
  )
    # Convert machines array into a string of "name:ip" pairs
    machine_args = machines.map { |machine| "#{machine[:name]}:#{machine[:network][:ip]}" }.join(" ")

    # Set up DNS and /etc/hosts with the machines
    node.vm.provision "setup-hosts", :type => "shell", :path => "configuration/os/#{os}/#{@provider}/setup-hosts.sh" do |s|
      s.args = [ip_nw, @network_mode, machine_args]
    end

    # Set up DNS resolution
    node.vm.provision "setup-dns", :type => "shell", :path => "configuration/os/#{os}/update-dns.sh"

    # Set up kernel parameters, modules, and tunables
    # node.vm.provision "setup-kernel", type: "shell", path: "ubuntu/setup-kernel.sh"

    # Set up ssh
    node.vm.provision "setup-ssh", :type => "shell", :path => "configuration/os/#{os}/ssh.sh"

    # Set up guest additions
    # node.vm.provision "setup-guest-additions", type: "shell", path: "ubuntu/vagrant/install-guest-additions.sh"
  end

  def define(
    os,
    ip_nw,
    machines
  )
    @config.vm.define @name do |node|
      node.vm.box = @box
      provider(node)

      node.vm.hostname = @hostname
      config_network(node)
      provision_vm(node, os, ip_nw, machines)
      provision_files(node)
    end
  end
end
