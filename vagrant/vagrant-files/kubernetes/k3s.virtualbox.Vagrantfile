# -*- mode: ruby -*-
# vi:set ft=ruby sw=2 ts=2 sts=2:

require_relative '../../utils/env'
require_relative '../../containers/virtualbox/virtualbox'
require_relative '../../containers/virtualbox/rhel'
require_relative '../../utils/machine/virtualbox_mc'

virtuaboxConfig = VirtualboxConfig.new
# virtuaboxConfig.display_config

# Define the number of slave clusters
# If this number is changed, remember to update setup-hosts.sh script with the new hosts IP details in /etc/hosts of each VM.
NUM_SERVERS = virtuaboxConfig.num_servers
NUM_AGENTS = virtuaboxConfig.num_agents

# Network parameters for NAT mode
IP_NW = virtuaboxConfig.ip_nw
# Host address start points
SERVER_IP_START = 10
AGENT_IP_START = 20
ETCD_IP_START = 30

# Define how much memory your computer has in GB (e.g., 8, 16)
# Larger clusters will be created if you have more.
RAM_SIZE = 8 # Replace with actual RAM size in GB

# Define how many CPU cores you have.
# More powerful nodes will be created if you have more.
CPU_CORES = 4 # Replace with actual CPU core count

# Ensure minimum required resources are met
MIN_RAM = 8 # GB
MIN_CPU = 4 # Cores

if RAM_SIZE < MIN_RAM
  raise "Insufficient memory #{RAM_SIZE}GB. Minimum required is #{MIN_RAM}GB."
end

if CPU_CORES < MIN_CPU
  raise "Insufficient CPU cores #{CPU_CORES}. Minimum required is #{MIN_CPU} cores."
end

# Calculate resources for master nodes
total_master_ram = (RAM_SIZE * 1024) * 0.25  # 25% of total RAM for all masters
total_master_cpu = CPU_CORES * 0.25          # 25% of total CPU for all masters

ram_per_master = (total_master_ram / NUM_SERVERS).to_i
cpu_per_master = (total_master_cpu / NUM_AGENTS).to_i

# Ensure minimum resources per master node
ram_per_master = [ram_per_master, 2048].max # At least 2 GB RAM per master
cpu_per_master = [cpu_per_master, 2].max    # At least 2 CPU cores per master

# Calculate resources for worker nodes
remaining_ram = (RAM_SIZE * 1024) - total_master_ram
remaining_cpu = CPU_CORES - total_master_cpu

ram_per_worker = (remaining_ram / NUM_AGENTS).to_i
cpu_per_worker = (remaining_cpu / NUM_AGENTS).to_i

# Ensure minimum resources per worker node
ram_per_worker = [ram_per_worker, 2048].max # At least 2 GB RAM per worker
cpu_per_worker = [cpu_per_worker, 1].max    # At least 1 CPU core per worker

# Resource allocation summary
RESOURCES = {
  server: {
    ram: ram_per_master, # RAM in MB per master node
    cpu: cpu_per_master, # CPU cores per master node
  },
  agent: {
    ram: ram_per_worker, # RAM in MB per worker node
    cpu: cpu_per_worker, # CPU cores per worker node
  },
  etcd: {
    ram: 1024, # RAM in MB
    cpu: 1, # CPU cores
  },
}

# Output the calculated resources
# NUM_SERVERS.times do |i|
#   puts "Server Node #{i+1} Resources: #{RESOURCES[:server][:ram]}MB RAM, #{RESOURCES[:server][:cpu]} CPU cores"
# end
# NUM_AGENTS.times do |i|
#   puts "Agent Node #{i+1} Resources: #{RESOURCES[:agent][:ram]}MB RAM, #{RESOURCES[:agent][:cpu]} CPU cores"
# end

machines = []
# machines.push(
#   {
#     name: "etcd-server",
#     box: virtuaboxConfig.os_systems[:redhat][:box],
#     os: virtuaboxConfig.os_systems[:redhat][:os],
#     cpu: RESOURCES[:etcd][:cpu],
#     ram: RESOURCES[:etcd][:ram],
#     network: {
#       name: "",
#       ports: [
#         # { guest: 22, host: 2740 + i },
#         { guest: 80, host: 8180 + 1},
#         { guest: 443, host: 4530 + 1 }
#       ],
#       ip: "#{IP_NW}.#{ETCD_IP_START + 1}"
#     },
#     files: [
#       { source: "./configuration/os/#{virtuaboxConfig.os_systems[:redhat][:os]}/.tmux.conf", destination: "$HOME/.tmux.conf" },
#       { source: "./configuration/os/#{virtuaboxConfig.os_systems[:redhat][:os]}/.vimrc", destination: "$HOME/.vimrc" }
#     ]
#   }
# )

(1..NUM_SERVERS).each do |i|
  machines.push(
    {
      name: "server-#{i}",
      box: virtuaboxConfig.os_systems[:redhat][:box],
      os: virtuaboxConfig.os_systems[:redhat][:os],
      cpu: RESOURCES[:server][:cpu],
      ram: RESOURCES[:server][:ram],
      network: {
        name: "",
        ports: [
          # { guest: 22, host: 2730 + i },
          { guest: 80, host: 8080 + i },
          { guest: 443, host: 4430 + i }
        ],
        ip: "#{IP_NW}.#{SERVER_IP_START + i}"
      },
      files: [
        { source: "./configuration/os/#{virtuaboxConfig.os_systems[:redhat][:os]}/.tmux.conf", destination: "$HOME/.tmux.conf" },
        { source: "./configuration/os/#{virtuaboxConfig.os_systems[:redhat][:os]}/.vimrc", destination: "$HOME/.vimrc" }
      ]
    }
  )
end

(1..NUM_AGENTS).each do |i|
  machines.push(
    {
      name: "agent-#{i}",
      box: virtuaboxConfig.os_systems[:redhat][:box],
      os: virtuaboxConfig.os_systems[:redhat][:os],
      cpu: RESOURCES[:agent][:cpu],
      ram: RESOURCES[:agent][:ram],
      network: {
        name: "",
        ports: [
          # { guest: 22, host: 2740 + i },
          { guest: 80, host: 8090 + i },
          { guest: 443, host: 4440 + i }
        ],
        ip: "#{IP_NW}.#{AGENT_IP_START + i}"
      },
      files: [
        { source: "./configuration/os/#{virtuaboxConfig.os_systems[:redhat][:os]}/.tmux.conf", destination: "$HOME/.tmux.conf" },
        { source: "./configuration/os/#{virtuaboxConfig.os_systems[:redhat][:os]}/.vimrc", destination: "$HOME/.vimrc" }
      ]
    }
  )
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
  config.vbguest.auto_update = false

  machines.each do |machine|
    vm = RhelVMVirtualbox.new(
      box = machine[:box],
      config = config,
      name = machine[:name],
      hostname = machine[:name],
      ip = machine[:network][:ip],
      network_mode = virtuaboxConfig.network_mode,
      vbox_guest_path = virtuaboxConfig.vbox_guest_disk,
      ports = machine[:network][:ports],
      provisioning_files = machine[:files],
      memory = machine[:ram],
      cpus = machine[:cpu],
    )

    vm.define(
      os = machine[:os],
      ip_nw = IP_NW,
      machines = machines,
      os_system_info = virtuaboxConfig.os_systems[:redhat]
    )
  end

  virtualMC = VirtualBoxMC.new(
    config = config,
    adapter = "",
    machines = machines,
    provider = virtuaboxConfig.provider,
    network_mode = virtuaboxConfig.network_mode
  )

  virtualMC.trigger
end
