# docker.rb
require_relative '../vm'

class DockerVM < VM
  attr_accessor :box, :env_vars, :volumes

  def initialize(
    box,
    config,
    name,
    hostname,
    ip,
    network_name,
    network_mode,
    ports = {},
    volumes = [],
    env_vars = {},
    provisioning_files = {},
    create_args = []
  )
    super(config, name, hostname, ip, network_mode, ports, provisioning_files)
    @box = box
    @network_name = network_name
    @env_vars = env_vars
    @volumes = volumes
    @create_args = create_args
  end

  def provider(node)
    node.vm.provider "docker" do |docker|
      docker.image = @env_vars.delete("DOCKER_IMG") || "ubuntu:latest"
      docker.remains_running = true
      docker.has_ssh = true
      docker.privileged = true
      docker.volumes = @volumes
      docker.env = @env_vars unless @env_vars.empty?
      docker.create_args = @create_args
    end
  end

  def define
    @config.vm.define @name do |node|

      provider(node)

      node.vm.hostname = @hostname
      private_network(node)
      forward_ports(node)
      provision_files(node)
    end
  end

  def public_network(node)
    node.vm.network :public_network, type: "dhcp"
  end

  def private_network(node)
    node.vm.network :private_network, ip: @ip, name: @network_name
  end

end
