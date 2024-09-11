# virtualbox.rb
require_relative 'vm'
require_relative '../utils/utils'

class RhelVM < VirtualBoxVM
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
    super(box, config, name, hostname, ip, network_mode, vbox_guest_path, ports, provisioning_files, memory, cpus, disk_size)
  end

  def provider(node)
    node.vm.provider "virtualbox" do |vb|
      vb.name = @name
      vb.memory = @memory
      vb.cpus = @cpus
      vb.customize ["storageattach", :id, "--storagectl", "IDE Controller", "--port", 1, "--device", 0, "--type", "dvddrive", "--medium", @vbox_guest_path]

      # vb.customize ["createhd", "--filename", "#{@name}.vdi", "--size", @disk_size * 1024]
      # vb.customize ["storagectl", :id, "--name", "SATA Controller", "--add", "sata", "--controller", "IntelAHCI"]
      # vb.customize ["storageattach", :id, "--storagectl", "SATA Controller", "--port", 0, "--device", 0, "--type", "hdd", "--medium", "#{@name}.vdi"]
    end
  end

  # Runs provisioning steps that are required by masters and slaves
  def provision_vm(
    node,
    os,
    ip_nw,
    machines,
    os_system_info
  )
    # Convert machines array into a string of "name:ip" pairs
    machine_args = machines.map { |machine| "#{machine[:name]}:#{machine[:network][:ip]}" }.join(" ")

    # node.vm.provision "shell", inline: <<-SHELL
    #   sudo subscription-manager register --username #{os_system_info[:rhelUsername]} --password #{os_system_info[:rhelPassword]} --auto-attach
    # SHELL

    # Set up DNS and /etc/hosts with the machines
    node.vm.provision "setup-hosts", :type => "shell", :path => "configuration/os/#{os}/#{@provider}/setup-hosts.sh" do |s|
      s.args = [ip_nw, @network_mode, machine_args]
    end

    # Set up DNS resolution
    node.vm.provision "setup-dns", :type => "shell", :path => "configuration/os/#{os}/update-dns.sh"

    # Set up kernel parameters, modules, and tunables
    # node.vm.provision "setup-kernel", type: "shell", path: "ubuntu/setup-kernel.sh"

    # Set up ssh
    node.vm.provision "setup-ssh", :type => "shell", :path => "configuration/os/#{os}/ssh.sh" do |s|
      s.args = [os_system_info[:rhelUsername], os_system_info[:rhelPassword]]
    end

    # Set up guest additions
    # node.vm.provision "setup-guest-additions", type: "shell", path: "ubuntu/vagrant/install-guest-additions.sh"
  end
end
