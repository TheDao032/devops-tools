# providers/vmware_fusion/rhel.rb
require_relative "vmware_fusion"
require_relative "../../utils/utils"

class RhelVMFusion < VMWareFusionVM
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

    rhel_username = ENV["RHEL_USERNAME"] || ""
    rhel_password = ENV["RHEL_PASSWORD"] || ""
    if !rhel_username.empty? && !rhel_password.empty?
      node.vm.provision "subscription-register", type: "shell", privileged: true,
                        inline: <<~SHELL
                          if ! subscription-manager status >/dev/null 2>&1; then
                            subscription-manager register --username='#{rhel_username}' --password='#{rhel_password}' --auto-attach || true
                          fi
                        SHELL
    end

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
