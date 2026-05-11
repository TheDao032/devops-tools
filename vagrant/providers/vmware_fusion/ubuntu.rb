# providers/vmware_fusion/ubuntu.rb
require_relative "vmware_fusion"
require_relative "../../utils/utils"

class UbuntuVMFusion < VMWareFusionVM
  include Utils

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
    super(box, config, name, hostname, ip, network_mode, ports,
          provisioning_files, memory, cpus)
  end

  def provision_vm(node, os, ip_nw, machines, _os_system_info)
    machine_args = machines.map { |m| "#{m[:name]}:#{m[:network][:ip]}" }.join(" ")

    node.vm.provision "setup-hosts", type: "shell",
                      path: "configuration/os/#{os}/#{@provider}/setup-hosts.sh" do |s|
      s.args = [ip_nw, @network_mode, machine_args]
    end

    node.vm.provision "setup-dns", type: "shell",
                      path: "configuration/os/#{os}/update-dns.sh"

    node.vm.provision "setup-ssh", type: "shell",
                      path: "configuration/os/#{os}/ssh.sh"
  end
end
