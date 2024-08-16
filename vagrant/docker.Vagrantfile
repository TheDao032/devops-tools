# -*- mode: ruby -*-
# vi:set ft=ruby sw=2 ts=2 sts=2:

# Docker image
DOCKER_IMG = "nthedao/ubuntu:latest"

# Define the number of slave clusters
# If this number is changed, remember to update setup-hosts.sh script with the new hosts IP details in /etc/hosts of each VM.
NUM_MASTER_CLUSTERS = 1
NUM_SLAVE_CLUSTERS = 2

# Host operating sysem detection
module OS
  def OS.windows?
    (/cygwin|mswin|mingw|bccwin|wince|emx/ =~ RUBY_PLATFORM) != nil
  end

  def OS.mac?
    (/darwin/ =~ RUBY_PLATFORM) != nil
  end

  def OS.unix?
    !OS.windows?
  end

  def OS.linux?
    OS.unix? and not OS.mac?
  end

  def OS.jruby?
    RUBY_ENGINE == "jruby"
  end
end

# Determine host adpater for bridging in BRIDGE mode
def get_bridge_adapter()
  if OS.windows?
    return %x{powershell -Command "Get-NetRoute -DestinationPrefix 0.0.0.0/0 | Get-NetAdapter | Select-Object -ExpandProperty InterfaceDescription"}.chomp
  elsif OS.linux?
    return %x{ip route | grep default | awk '{ print $5 }'}.chomp
  elsif OS.mac?
    return %x{macos/macos-bridge.sh}.chomp
  end
end

# Helper method to get the machine ID of a node.
# This will only be present if the node has been
# created in VirtualBox.
def get_machine_id(vm_name)
  machine_id_filepath = ".vagrant/machines/#{vm_name}/virtualbox/id"
  if not File.exist? machine_id_filepath
    return nil
  else
    return File.read(machine_id_filepath)
  end
end

# Helper method to determine whether all clusters are up
def all_clusters_up()
  (1..NUM_MASTER_CLUSTERS).each do |i|
    if get_machine_id("master#{i}").nil?
      return false
    end
  end

  (1..NUM_SLAVE_CLUSTERS).each do |i|
    if get_machine_id("slave#{i}").nil?
      return false
    end
  end
  return true
end

# Sets up hosts file and DNS
def setup_dns(node)
  # Set up /etc/hosts
  node.vm.provision "setup-hosts", :type => "shell", :path => "ubuntu/vagrant/setup-hosts.sh" do |s|
    s.args = [NUM_MASTER_CLUSTERS, NUM_SLAVE_CLUSTERS]
  end
  # Set up DNS resolution
  node.vm.provision "setup-dns", type: "shell", :path => "ubuntu/update-dns.sh"
end

# Runs provisioning steps that are required by masters and slaves
def provision_kubernetes_node(node)
  # Set up DNS
  setup_dns node
  # Set up kernel parameters, modules and tunables
  # node.vm.provision "setup-kernel", :type => "shell", :path => "ubuntu/setup-kernel.sh"
  # Set up ssh
  node.vm.provision "setup-ssh", :type => "shell", :path => "ubuntu/ssh.sh"
  # Set up guest additions
  # node.vm.provision "setup-guest-additions", :type => "shell", :path => "ubuntu/vagrant/install-guest-additions.sh"
end

# All Vagrant configuration is done below. The "2" in Vagrant.configure
# configures the configuration version (we support older styles for
# backwards compatibility). Please don't change it unless you know what
# you're doing.
Vagrant.configure("2") do |config|
  # The most common configuration options are documented and commented below.
  # For a complete reference, please see the online documentation at
  # https://docs.vagrantup.com.

  # Every Vagrant development environment requires a box. You can search for
  # boxes at https://vagrantcloud.com/search.
  # config.vm.box = "base"

  # config.vm.box = "nthedao/ubuntu-latest"
  config.vm.boot_timeout = 900

  # Disable automatic box update checking. If you disable this, then
  # boxes will only be checked for updates when the user runs
  # `vagrant box outdated`. This is not recommended.
  config.vm.box_check_update = false
  config.vbguest.auto_update = true

  # Provision Master Clusters
  (1..NUM_MASTER_CLUSTERS).each do |i|
    config.vm.define "master-docker-#{i}" do |node|
      # Name shown in the GUI
      config.vm.provider "docker" do |docker|
        docker.image = DOCKER_IMG
        # docker.build_dir = "."
        docker.remains_running = true
        docker.has_ssh = false
        docker.privileged = true
        # docker.ports = ["#{2250 + i}:2222"]
      end

      node.vm.hostname = "master#{i}"
      node.vm.network :forwarded_port, id: "ssh", guest: 22, host: "#{2750 + i}"
      node.vm.network :forwarded_port, guest: 5432, host: "#{5432 + i}"
      # provision_kubernetes_node node

      # Install (opinionated) configs for vim and tmux on master-1. These used by the author for CKA exam.
      node.vm.provision "file", source: "./ubuntu/.tmux.conf", destination: "$HOME/.tmux.conf"
      node.vm.provision "file", source: "./ubuntu/.vimrc", destination: "$HOME/.vimrc"
    end
  end

  # Provision Slave Clusters
  (1..NUM_SLAVE_CLUSTERS).each do |i|
    config.vm.define "slave-docker-#{i}" do |node|

      config.vm.provider "docker" do |docker|
        docker.image = DOCKER_IMG
        # docker.build_dir = "."
        docker.remains_running = true
        docker.has_ssh = false
        docker.privileged = true
      end

      node.vm.hostname = "slave#{i}"
      node.vm.network :forwarded_port, id: "ssh", guest: 22, host: "#{2760 + i}"
      node.vm.network :forwarded_port, guest: 5432, host: "#{5442 + i}"
      # provision_kubernetes_node node

      node.vm.provision "file", source: "./ubuntu/.tmux.conf", destination: "$HOME/.tmux.conf"
      node.vm.provision "file", source: "./ubuntu/.vimrc", destination: "$HOME/.vimrc"
    end
  end

  # config.trigger.after :up do |trigger|
  #   trigger.name = "Post provisioner"
  #   trigger.ignore = [:destroy, :halt]
  #   trigger.ruby do |env, machine|
  #     if all_clusters_up()
  #       puts "    Gathering IP addresses of clusters..."
  #       clusters = []
  #       ips = []
  #       (1..NUM_MASTER_CLUSTERS).each do |i|
  #         clusters.push("master#{i}")
  #       end
  #       (1..NUM_SLAVE_CLUSTERS).each do |i|
  #         clusters.push("slave#{i}")
  #       end
  #       clusters.each do |n|
  #         ips.push(%x{vagrant ssh #{n} -c 'public-ip'}.chomp)
  #       end
  #       hosts = ""
  #       ips.each_with_index do |ip, i|
  #         hosts << ip << "  " << clusters[i] << "\n"
  #       end
  #       puts "    Setting /etc/hosts on clusters..."
  #       File.open("hosts.tmp", "w") { |file| file.write(hosts) }
  #       clusters.each do |node|
  #         system("vagrant upload hosts.tmp /tmp/hosts.tmp #{node}")
  #         system("vagrant ssh #{node} -c 'cat /tmp/hosts.tmp | sudo tee -a /etc/hosts'")
  #         system("vagrant upload ~/.ssh/id_rsa.pub /tmp/id_rsa.pub #{node}")
  #         system("vagrant ssh #{node} -c 'cat /tmp/id_rsa.pub >> /home/vagrant/.ssh/authorized_keys'")
  #       end
  #       File.delete("hosts.tmp")
  #       puts <<~EOF
  #
  #              VM build complete!
  #
  #              Use either of the following to access any NodePort services you create from your browser
  #              replacing "port_number" with the number of your NodePort.
  #
  #            EOF
  #       (1..ips.length).each do |i|
  #         puts "  http://#{ips[i]}:port_number"
  #       end
  #       puts ""
  #     else
  #       puts "    Nothing to do here"
  #     end
  #   end
  # end
end
