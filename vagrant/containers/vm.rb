# vm.rb

class VM
  attr_accessor :config, :name, :hostname, :ip, :network_mode, :ports, :provisioning_files
  def initialize(config, name, hostname, ip, network_mode, ports = [], provisioning_files = [])
    @config = config
    @name = name
    @hostname = hostname
    @ip = ip
    @network_mode = network_mode
    @ports = ports
    @provisioning_files = provisioning_files
  end

  def define
    raise NotImplementedError, "Subclasses must implement the define method"
  end

  def provider(node)
    raise NotImplementedError, "Subclasses must implement the define method"
  end

  def config_network(node, network_mode)
    raise NotImplementedError, "Subclasses must implement the define method"
  end

  def public_network(node)
    raise NotImplementedError, "Subclasses must implement the define method"
  end

  def private_network(node)
    raise NotImplementedError, "Subclasses must implement the define method"
  end

  def forward_ports(node)
    @ports.each do |port|
      node.vm.network :forwarded_port, guest: port[:guest], host: port[:host]
    end
  end

  def provision_files(node)
    @provisioning_files.each do |file|
      node.vm.provision "file", source: file[:source], destination: file[:destination]
    end
  end

  def provision_vm(node, os)
    raise NotImplementedError, "Subclasses must implement the define method"
  end
end
