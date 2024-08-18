# -*- mode: ruby -*-
# vi:set ft=ruby sw=2 ts=2 sts=2:

# Docker image
VAGRANT_PROVIDER = "docker"
DOCKER_IMG = "nthedao/ubuntu:latest"
DOCKER_NETWORK_NAME = "vagrant"
DOCKER_NETWORK_SUBNET = "172.20.10.0/24"
DOCKER_NETWORK = "172.20.10"

# Define the number of slave clusters
# If this number is changed, remember to update setup-hosts.sh script with the new hosts IP details in /etc/hosts of each VM.
NUM_MASTER_CLUSTERS = 1
NUM_SLAVE_CLUSTERS = 2

MASTER_IP_START = 10
SLAVE_IP_START = 20

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
# created in Docker.
def get_machine_id(vm_name)
  machine_id_filepath = ".vagrant/machines/#{vm_name}/#{VAGRANT_PROVIDER}/id"
  if not File.exist? machine_id_filepath
    return nil
  else
    return File.read(machine_id_filepath)
  end
end

# Helper method to determine whether all clusters are up
def all_clusters_up()
  (1..NUM_MASTER_CLUSTERS).each do |i|
    if get_machine_id("master-docker-#{i}").nil?
      return false
    end
  end

  (1..NUM_SLAVE_CLUSTERS).each do |i|
    if get_machine_id("slave-docker-#{i}").nil?
      return false
    end
  end
  return true
end

# Sets up hosts file and DNS
def setup_dns(node)
  # Set up /etc/hosts
  node.vm.provision "setup-hosts", :type => "shell", :path => "ubuntu/#{VAGRANT_PROVIDER}/setup-hosts.sh" do |s|
    s.args = [DOCKER_NETWORK_SUBNET, NUM_MASTER_CLUSTERS, NUM_SLAVE_CLUSTERS]
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
        # docker.name = "master-docker-#{i}"
        docker.image = DOCKER_IMG
        # docker.build_dir = "."
        docker.remains_running = true
        docker.has_ssh = false
        docker.privileged = true
        # docker.ports = ["#{2250 + i}:2222"]
      end

      node.vm.hostname = "master-docker-#{i}"
      node.vm.network :private_network, ip: "#{DOCKER_NETWORK}.#{MASTER_IP_START + i}", name: DOCKER_NETWORK_NAME
      node.vm.network :forwarded_port, guest: 22, host: "#{2750 + i}"
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
        # docker.name = "slave-docker-#{i}"
        docker.image = DOCKER_IMG
        # docker.build_dir = "."
        docker.remains_running = true
        docker.has_ssh = false
        docker.privileged = true
      end

      node.vm.hostname = "slave-docker-#{i}"
      node.vm.network :private_network, ip: "#{DOCKER_NETWORK}.#{SLAVE_IP_START + i}", name: DOCKER_NETWORK_NAME
      node.vm.network :forwarded_port, guest: 22, host: "#{2760 + i}"
      node.vm.network :forwarded_port, guest: 5432, host: "#{5442 + i}"
      # provision_kubernetes_node node

      node.vm.provision "file", source: "./ubuntu/.tmux.conf", destination: "$HOME/.tmux.conf"
      node.vm.provision "file", source: "./ubuntu/.vimrc", destination: "$HOME/.vimrc"
    end
  end

  config.trigger.after :up do |trigger|
    trigger.name = "Post provisioner"
    trigger.ignore = [:destroy, :halt]
    trigger.ruby do |env, machine|
      if all_clusters_up()
        puts "    Gathering IP addresses of clusters..."
        clusters = []
        container_ids = []
        ips = []

        # Collecting cluster names
        (1..NUM_MASTER_CLUSTERS).each do |i|
          clusters.push("master-docker-#{i}")
        end
        (1..NUM_SLAVE_CLUSTERS).each do |i|
          clusters.push("slave-docker-#{i}")
        end

        # Retrieve container IDs and IPs using Docker CLI
        clusters.each do |n|
          container_id = %x{docker ps --filter "name=#{n}" --format "{{.ID}}"}.chomp
          container_ids.push(container_id)
          ip = %x{docker inspect -f '{{.NetworkSettings.Networks.#{DOCKER_NETWORK_NAME}.IPAddress}}' #{container_id}}.chomp
          ips.push(ip)
        end

        puts "container_ids: #{container_ids}"

        # Prepare the hosts file content
        hosts = ""
        ips.each_with_index do |ip, i|
          hosts << ip << "  " << clusters[i] << "\n"
        end

        # unique_ips = ips.uniq
        #
        # # Prepare the hosts file content
        # hosts = unique_ips.join("\n")
        # puts "hosts: #{hosts}"

        # Create hosts.tmp file
        begin
          File.open("hosts.tmp.#{machine.name}", "w") { |file| file.write(hosts) }
          puts "hosts.tmp file created successfully."
        rescue => e
          puts "Error creating hosts.tmp file: #{e.message}"
          raise
        end

        # Output and set /etc/hosts on each container
        puts "    Setting /etc/hosts on clusters..."
        # clusters.each do |cluster|
        container_id = %x{docker ps --filter "name=#{machine.name}" --format "{{.ID}}"}.chomp
        if File.exist?("hosts.tmp.#{machine.name}")
          system("docker cp hosts.tmp.#{machine.name} #{container_id}:/tmp/hosts.tmp")
          system("docker exec #{container_id} bash -c 'cat /tmp/hosts.tmp | sudo tee -a /etc/hosts'")
          system("docker cp ~/.ssh/id_rsa.pub #{container_id}:/tmp/id_rsa.pub")
          system("docker exec #{container_id} bash -c 'cat /tmp/id_rsa.pub >> /home/vagrant/.ssh/authorized_keys'")
        else
          puts "hosts.tmp file not found, skipping container #{container_id}."
        end
        # end

        # Clean up
        if File.exist?("hosts.tmp.#{machine.name}")
          File.delete("hosts.tmp.#{machine.name}")
          puts "hosts.tmp.#{machine.name} file deleted successfully."
        else
          puts "hosts.tmp.#{machine.name} file not found during cleanup."
        end

        puts <<~EOF

               VM build complete!

               Use either of the following to access any NodePort services you create from your browser
               replacing "port_number" with the number of your NodePort.

             EOF
        ips.each do |ip|
          puts "  http://#{ip}:port_number"
        end
        puts ""
      else
        puts "    Nothing to do here"
      end
    end
  end
end
