class Config
  attr_accessor :provider, :network_mode, :num_servers, :num_agents, :ubuntu, :centos, :redhat

  def initialize
    @provider = ENV["PROVIDER"] || "default_provider"

    # "BRIDGE" - Places VMs on your local network so cluster can be accessed from browser.
    #            You must have enough spare IPs on your network for the clusters.
    # "NAT"    - Places VMs in a private virtual network. Cluster cannot be accessed
    #            without setting up a port forwarding rule for every NodePort exposed.
    #            Use this mode if for some reason BRIDGE doesn't work for you.
    @network_mode = ENV["NETWORK_MODE"] || "default_mode"
    @num_servers = ENV["NUM_SERVERS"] || 1
    @num_agents = ENV["NUM_AGENTS"] || 1
    @ubuntu = {
      jammy_box: "ubuntu/jammy64",
      focal_box: "ubuntu/focal64",
      bionic_box: "ubuntu/bionic64",
      os: "ubuntu"
    }
    @centos = {
      box: "centos/7",
      os: "centos"
    }
    @redhat = {
      box: "alvistack/rhel-9",
        os: "rhel",
        rhelUsername: ENV['RHEL_USERNAME'] || "dump_user",
        rhelPassword: ENV['RHEL_PASSWORD'] || "dump_password"
    }
  end

  def display_config
    puts "Provider: #{@provider}"
    puts "Network Mode: #{@network_mode}"
  end
end

class DockerConfig < Config
  attr_accessor :repository, :img_name, :img_tag, :docker_img, :docker_network_name, :docker_network_subnet, :docker_network

  def initialize
    super
    @repository = ENV["REPOSITORY"] || "nthedao"
    @img_name = ENV["IMAGE"] || "ubuntu-22.04"
    @img_tag = ENV["TAG"] || "latest"
    @docker_img = "#{@repository}/#{@img_name}:#{@img_tag}"
    @docker_network_name = ENV["DOCKER_NETWORK_NAME"] || "vagrant"
    @docker_network_subnet = ENV["DOCKER_NETWORK_SUBNET"] || "172.20.10.0/24"
    @docker_network = ENV["DOCKER_NETWORK"] || "172.20.10"
  end

  def display_config
    super
    puts "Repository: #{@repository}"
    puts "Image Name: #{@img_name}"
    puts "Image Tag: #{@img_tag}"
    puts "Docker Image: #{@docker_img}"
    puts "Docker Network Name: #{@docker_network_name}"
    puts "Docker Network Subnet: #{@docker_network_subnet}"
    puts "Docker Network: #{@docker_network}"
  end
end

class VirtualboxConfig < Config
  attr_accessor :vbox_guest_disk, :ip_nw

  def initialize
    super

    # VBoxGuest
    @ip_nw = ENV["IP_NW"] || '192.168.56'
    @vbox_guest_disk = ENV["VBOX_GUEST_DISK"] || "/Applications/VirtualBox.app/Contents/MacOS/VBoxGuestAdditions.iso"
  end

  def display_config
    super
    puts "Repository: #{@vbox_guest_disk}"
    puts "IP Network: #{@ip_nw}"
  end
end

class VMWareFusionConfig < Config
  attr_accessor :ip_nw

  def initialize
    super

    @ip_nw = ENV["IP_NW"] || '192.168.10'
  end

  def display_config
    super
    puts "Ip Network: #{@ip_nw}"
  end
end
