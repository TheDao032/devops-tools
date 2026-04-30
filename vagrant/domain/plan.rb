module VagrantDomain
  class ResourceSpec
    attr_reader :ram, :cpu

    def initialize(ram:, cpu:)
      @ram = Integer(ram)
      @cpu = Integer(cpu)
    end
  end

  class NetworkSpec
    attr_reader :ip, :ports, :name

    def initialize(ip:, ports: [], name: "")
      @ip = ip
      @name = name.to_s
      @ports = ports.map do |port|
        {
          guest: port.fetch(:guest),
          host: port.fetch(:host)
        }
      end
    end

    def to_h
      {
        ip: @ip,
        name: @name,
        ports: @ports
      }
    end
  end

  class FileProvisionSpec
    attr_reader :source, :destination

    def initialize(source:, destination:)
      @source = source
      @destination = destination
    end

    def to_h
      {
        source: @source,
        destination: @destination
      }
    end
  end

  class MachineSpec
    attr_reader :name, :box, :os_key, :os_name, :resources, :network, :files, :metadata

    def initialize(name:, box:, os_key:, os_name:, resources:, network:, files: [], metadata: {})
      @name = name
      @box = box
      @os_key = os_key
      @os_name = os_name
      @resources = resources
      @network = network
      @files = files
      @metadata = metadata
    end

    def to_legacy_hash
      {
        name: @name,
        box: @box,
        os: @os_name,
        cpu: @resources.cpu,
        ram: @resources.ram,
        network: @network.to_h,
        files: @files.map(&:to_h),
        metadata: @metadata
      }
    end
  end

  class ClusterPlan
    attr_reader :adapter_type, :provider_name, :network_mode, :ip_nw, :machines,
                :os_catalog, :boot_timeout, :box_check_update, :vbguest_auto_update,
                :runtime_options

    def initialize(
      adapter_type:,
      provider_name:,
      network_mode:,
      ip_nw:,
      machines:,
      os_catalog:,
      boot_timeout: 900,
      box_check_update: false,
      vbguest_auto_update: false,
      runtime_options: {}
    )
      @adapter_type = adapter_type
      @provider_name = provider_name
      @network_mode = network_mode
      @ip_nw = ip_nw
      @machines = machines
      @os_catalog = os_catalog
      @boot_timeout = boot_timeout
      @box_check_update = box_check_update
      @vbguest_auto_update = vbguest_auto_update
      @runtime_options = runtime_options
    end

    def legacy_machines
      @machines.map(&:to_legacy_hash)
    end
  end
end
