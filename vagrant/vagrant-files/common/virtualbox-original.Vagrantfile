# -*- mode: ruby -*-
# vi:set ft=ruby sw=2 ts=2 sts=2:

UBUNTU_BOX = "ubuntu/jammy64"
RHEL_BOX = "alvistack/rhel-9"

# require 'getoptlong'
#
# opts = GetoptLong.new(
#   [ '--rhel-username', GetoptLong::OPTIONAL_ARGUMENT ],
#   [ '--rhel-password', GetoptLong::OPTIONAL_ARGUMENT ],
#   [ '--force', '-f', GetoptLong::NO_ARGUMENT ]
# )

# rhelUsername = ENV['RHEL_USERNAME']
# rhelPassword = ENV['RHEL_PASSWORD']

# opts.each do |opt, arg|
#   case opt
#     when '--rhel-username'
#       rhelUsername=arg
#     when '--rhel-password'
#       rhelPassword=arg
#   end
# end

# RHEL Env Vars

# Vagrant provider
PROVIDER = "virtualbox"

# Set the build mode
# "BRIDGE" - Places VMs on your local network so cluster can be accessed from browser.
#            You must have enough spare IPs on your network for the clusters.
# "NAT"    - Places VMs in a private virtual network. Cluster cannot be accessed
#            without setting up a port forwarding rule for every NodePort exposed.
#            Use this mode if for some reason BRIDGE doesn't work for you.
BUILD_MODE = "NAT"

# Define how much memory your computer has in GB (e.g. 8, 16)
# Larger clusters will be created if you have more.
RAM_SIZE = 16

# Define how mnay CPU cores you have.
# More powerful slaves will be created if you have more
CPU_CORES = 8

# VBoxGuest
# VBOX_GUEST_DISK_PATH = "/Applications/VirtualBox.app/Contents/MacOS/VBoxGuestAdditions.iso"
VBOX_GUEST_DISK_PATH = "C:\Program Files\Oracle\VirtualBox\VBoxGuestAdditions.iso"

# Define the number of slave clusters
# If this number is changed, remember to update setup-hosts.sh script with the new hosts IP details in /etc/hosts of each VM.
NUM_MASTER_CLUSTERS = 1
NUM_SLAVE_CLUSTERS = 1

# Network parameters for NAT mode
IP_NW = "192.168.10"
# Host address start points
MASTER_IP_START = 10
SLAVE_IP_START = 20

# Calculate resource amounts
# based on RAM/CPU
ram_selector = (RAM_SIZE / 4) * 4
if ram_selector < 8
  raise "Unsufficient memory #{RAM_SIZE}GB. min 8GB"
end
RESOURCES = {
  "master" => {
    1 => {
      # master1 bigger since it may run e2e tests.
      "ram" => [ram_selector * 128, 2048].max(),
      "cpu" => CPU_CORES >= 12 ? 4 : 2,
    },
  },
  "slave" => {
    "ram" => [ram_selector * 128, 4096].min(),
    "cpu" => (((CPU_CORES / 4) * 4) - 4) / 4,
  },
}

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
    return %x{configuration/networks/#{PROVIDER}/macos/macos-bridge.sh}.chomp
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
def setup_dns(node, os)
  # Set up /etc/hosts
  node.vm.provision "setup-hosts", :type => "shell", :path => "configuration/os/#{os}/#{PROVIDER}/setup-hosts.sh" do |s|
    s.args = [IP_NW, BUILD_MODE, NUM_MASTER_CLUSTERS, NUM_SLAVE_CLUSTERS, MASTER_IP_START, SLAVE_IP_START]
  end
  # Set up DNS resolution
  node.vm.provision "setup-dns", type: "shell", :path => "configuration/os/#{os}/update-dns.sh"
end

# Runs provisioning steps that are required by masters and slaves
def provision_ubuntu_vm(node, os)
  # Set up DNS
  setup_dns(node, "ubuntu")
  # Set up kernel parameters, modules and tunables
  # node.vm.provision "setup-kernel", :type => "shell", :path => "ubuntu/setup-kernel.sh"
  # Set up ssh
  node.vm.provision "setup-ssh", :type => "shell", :path => "configuration/os/#{os}/ssh.sh"
  # Set up guest additions
  # node.vm.provision "setup-guest-additions", :type => "shell", :path => "ubuntu/vagrant/install-guest-additions.sh"
end

def provision_rhel_vm(node, os)
  # Set up DNS
  setup_dns(node, "rhel")
  # Set up kernel parameters, modules and tunables
  # node.vm.provision "setup-kernel", :type => "shell", :path => "ubuntu/setup-kernel.sh"
  # Set up ssh
  node.vm.provision "setup-ssh", :type => "shell", :path => "configuration/os/#{os}/ssh.sh"
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

  config.vm.boot_timeout = 900

  # Disable automatic box update checking. If you disable this, then
  # boxes will only be checked for updates when the user runs
  # `vagrant box outdated`. This is not recommended.
  config.vm.box_check_update = false
  config.vbguest.auto_update = true

  # Provision Master Clusters
  (1..NUM_MASTER_CLUSTERS).each do |i|
    config.vm.define "master#{i}" do |node|
      # Name shown in the GUI
      node.vm.box = "#{UBUNTU_BOX}"
      node.vm.provider "virtualbox" do |vb|
        vb.name = "master#{i}"
        vb.memory = RESOURCES["master"][i > 2 ? 2 : i]["ram"]
        vb.cpus = RESOURCES["master"][i > 2 ? 2 : i]["cpu"]
        vb.customize ["storageattach", :id, "--storagectl", "IDE", "--port", 1, "--device", 0, "--type", "dvddrive", "--medium", VBOX_GUEST_DISK_PATH]
      end

      # config.vm.provision "shell", inline: <<-SHELL
      #   if ! mount | grep -q "/mnt"; then
      #     sudo mkdir -p /mnt
      #     sudo mount /dev/cdrom /mnt
      #     sudo apt install bzip2 -y
      #     sudo sh /mnt/VBoxLinuxAdditions.run || true
      #   fi
      # SHELL

      node.vm.hostname = "master#{i}"
      if BUILD_MODE == "BRIDGE"
        adapter = ""
        node.vm.network :public_network, bridge: get_bridge_adapter()
      else
        node.vm.network :private_network, ip: IP_NW + ".#{MASTER_IP_START + i}"
        node.vm.network "forwarded_port", guest: 22, host: "#{2730 + i}"
      end
      os = "ubuntu"
      provision_ubuntu_vm(node, os)
      # Install (opinionated) configs for vim and tmux on master-1. These used by the author for CKA exam.
      if i == 1
        node.vm.provision "file", source: "./configuration/os/#{os}/.tmux.conf", destination: "$HOME/.tmux.conf"
        node.vm.provision "file", source: "./configuration/os/#{os}/.vimrc", destination: "$HOME/.vimrc"
      end
    end
  end

  # Provision Slave Clusters
  (1..NUM_SLAVE_CLUSTERS).each do |i|
    config.vm.define "slave#{i}" do |node|
      node.vm.box = "#{UBUNTU_BOX}"
      node.vm.provider "virtualbox" do |vb|
        vb.name = "slave#{i}"
        vb.memory = RESOURCES["slave"]["ram"]
        vb.cpus = RESOURCES["slave"]["cpu"]
        vb.customize ["storageattach", :id, "--storagectl", "IDE", "--port", 1, "--device", 0, "--type", "dvddrive", "--medium", VBOX_GUEST_DISK_PATH]
        # vb.customize ["storageattach", :id, "--storagectl", "IDE Controller", "--port", 1, "--device", 0, "--type", "dvddrive", "--medium", VBOX_GUEST_DISK_PATH] # RHEL_POX
      end

      # node.vm.provision "shell", inline: <<-SHELL
      #   sudo subscription-manager register --username #{rhelUsername} --password #{rhelPassword}
      # SHELL

      node.vm.hostname = "slave#{i}"
      if BUILD_MODE == "BRIDGE"
        node.vm.network :public_network, bridge: get_bridge_adapter()
      else
        node.vm.network :private_network, ip: IP_NW + ".#{SLAVE_IP_START + i}"
        node.vm.network "forwarded_port", guest: 22, host: "#{2740 + i}"
      end

      # node.vm.provision "setup-hosts", :type => "shell", :path => "ubuntu/#{PROVIDER}/setup-hosts.sh" do |s|
      #   s.args = [IP_NW, BUILD_MODE, NUM_MASTER_CLUSTERS, NUM_SLAVE_CLUSTERS, MASTER_IP_START, SLAVE_IP_START]
      # end
      # node.vm.provision "setup-ssh", :type => "shell", :path => "ubuntu/ssh.sh"
      provision_rhel_vm(node, "rhel")
    end
  end

  if BUILD_MODE == "BRIDGE"
    # Trigger that fires after each VM starts.
    # Does nothing until all the VMs have started, at which point it
    # gathers the IP addresses assigned to the bridge interfaces by DHCP
    # and pushes a hosts file to each node with these IPs.
    config.trigger.after :up do |trigger|
      trigger.name = "Post provisioner"
      trigger.ignore = [:destroy, :halt]
      trigger.ruby do |env, machine|
        if all_clusters_up()
          puts "    Gathering IP addresses of clusters..."
          clusters = []
          ips = []
          (1..NUM_MASTER_CLUSTERS).each do |i|
            clusters.push("master#{i}")
          end
          (1..NUM_SLAVE_CLUSTERS).each do |i|
            clusters.push("slave#{i}")
          end
          clusters.each do |n|
            ips.push(%x{vagrant ssh #{n} -c 'public-ip'}.chomp)
          end
          hosts = ""
          ips.each_with_index do |ip, i|
            hosts << ip << "  " << clusters[i] << "\n"
          end
          puts "    Setting /etc/hosts on clusters..."
          File.open("hosts.tmp", "w") { |file| file.write(hosts) }
          clusters.each do |node|
            system("vagrant upload hosts.tmp /tmp/hosts.tmp #{node}")
            system("vagrant ssh #{node} -c 'cat /tmp/hosts.tmp | sudo tee -a /etc/hosts'")
            system("vagrant upload ~/.ssh/id_rsa.pub /tmp/id_rsa.pub #{node}")
            system("vagrant ssh #{node} -c 'cat /tmp/id_rsa.pub >> /home/vagrant/.ssh/authorized_keys'")
          end
          File.delete("hosts.tmp")
          puts <<~EOF

                 VM build complete!

                 Use either of the following to access any NodePort services you create from your browser
                 replacing "port_number" with the number of your NodePort.

               EOF
          (1..ips.length).each do |i|
            puts "  http://#{ips[i]}:port_number"
          end
          puts ""
        else
          puts "    Nothing to do here"
        end
      end
    end
  else
    config.trigger.after :up do |trigger|
      trigger.name = "Post provisioner"
      trigger.ignore = [:destroy, :halt]
      trigger.ruby do |env, machine|
        if all_clusters_up()
          puts "    Gathering IP addresses of clusters..."
          clusters = []
          ips = []
          (1..NUM_MASTER_CLUSTERS).each do |i|
            clusters.push("master#{i}")
          end
          (1..NUM_SLAVE_CLUSTERS).each do |i|
            clusters.push("slave#{i}")
          end
          clusters.each do |node|
            # ips.push(%x{vagrant ssh #{node} -c 'public-ip'}.chomp)
            system("vagrant upload ~/.ssh/id_rsa.pub /tmp/id_rsa.pub #{node}")
            system("vagrant ssh #{node} -c 'cat /tmp/id_rsa.pub >> /home/vagrant/.ssh/authorized_keys'")
          end
          puts <<~EOF

                 VM build complete!

                 Use either of the following to access any NodePort services you create from your browser
                 replacing "port_number" with the number of your NodePort.

               EOF
        else
          puts "    Nothing to do here"
        end
      end
    end
  end
end
