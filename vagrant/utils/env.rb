require "rbconfig"

class Config
  attr_accessor :provider, :network_mode, :num_servers, :num_agents, :ubuntu, :centos, :redhat, :architecture, :resource_profile

  def initialize
    @provider = ENV["PROVIDER"] || "default_provider"

    # "BRIDGE" - Places VMs on your local network so cluster can be accessed from browser.
    #            You must have enough spare IPs on your network for the clusters.
    # "NAT"    - Places VMs in a private virtual network. Cluster cannot be accessed
    #            without setting up a port forwarding rule for every NodePort exposed.
    #            Use this mode if for some reason BRIDGE doesn't work for you.
    @network_mode = ENV["NETWORK_MODE"] || "NAT"
    @num_servers = ENV["NUM_SERVERS"] || 2
    @num_agents = ENV["NUM_AGENTS"] || 1
    @architecture = normalize_architecture(ENV["ARCH"]) || host_architecture
    # Resource profile name (:low | :medium | :high) — drives per-role RAM/CPU
    # via VagrantApplication::ResourceProfile. Defaults to :medium so existing
    # callers see no behavior change. The catalog itself lives in
    # vagrant/application/resource_profile.rb (validation happens there).
    @resource_profile = (ENV["RESOURCE_PROFILE"] || "medium").to_sym
    @ubuntu = {
      noble_numbat_box: {
        arm64: "bento/ubuntu-24.04",
        amd64: ""
      },
      jammy_box: {
        arm64: "bento/ubuntu-22.04",
        amd64: "ubuntu/jammy64"
      },
      focal_box: {
        arm64: "bento/ubuntu-20.04",
        amd64: "ubuntu/focal64"
      },
      bionic_box: {
        arm64: "bento/ubuntu-18.04",
        amd64: "ubuntu/bionic64",
      },
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
    puts "Architecture: #{@architecture}"
    puts "Resource Profile: #{@resource_profile}"
  end

  def ubuntu_box(version = :jammy_box)
    box_config = @ubuntu.fetch(version)
    box = box_config.fetch(@architecture, "")
    box = box_config.fetch(:amd64, "") if box.empty?

    raise KeyError, "Ubuntu box '#{version}' is not configured for #{@architecture}" if box.empty?

    box
  end

  def os_systems
    {
      ubuntu: {
        box: ubuntu_box,
        os: @ubuntu[:os]
      },
      centos: @centos,
      redhat: @redhat
    }
  end

  def os_info(key)
    case key.to_sym
    when :ubuntu
      @ubuntu
    when :centos
      @centos
    when :redhat
      @redhat
    else
      raise KeyError, "Unknown OS key: #{key}"
    end
  end

  def [](key)
    case key.to_sym
    when :ubuntu
      os_systems[:ubuntu]
    when :centos
      @centos
    when :redhat
      @redhat
    else
      raise KeyError, "Unknown config key: #{key}"
    end
  end

  private

  def normalize_architecture(value)
    case value.to_s.downcase
    when "arm64", "aarch64"
      :arm64
    when "amd64", "x86_64"
      :amd64
    end
  end

  def host_architecture
    normalize_architecture(RbConfig::CONFIG["host_cpu"]) || :amd64
  end
end

class DockerConfig < Config
  attr_accessor :repository, :img_name, :img_tag, :docker_img, :docker_network_name, :docker_network_subnet, :docker_network

  def initialize
    super
    @provider = ENV["PROVIDER"] || "docker"
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
    @provider = ENV["PROVIDER"] || "virtualbox"

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
    @provider = ENV["PROVIDER"] || "vmware_fusion"

    @ip_nw = ENV["IP_NW"] || '192.168.10'
  end

  def display_config
    super
    puts "Ip Network: #{@ip_nw}"
  end
end
