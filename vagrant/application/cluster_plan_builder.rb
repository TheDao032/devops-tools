require_relative "../domain/plan"

module VagrantApplication
  class ClusterPlanBuilder
    def initialize(
      config:,
      adapter_type:,
      ip_nw:,
      resource_profiles:,
      machine_groups:,
      boot_timeout: 900,
      box_check_update: false,
      vbguest_auto_update: false,
      runtime_options: {}
    )
      @config = config
      @adapter_type = adapter_type
      @ip_nw = ip_nw
      @resource_profiles = resource_profiles
      @machine_groups = machine_groups
      @boot_timeout = boot_timeout
      @box_check_update = box_check_update
      @vbguest_auto_update = vbguest_auto_update
      @runtime_options = runtime_options
    end

    def build
      VagrantDomain::ClusterPlan.new(
        adapter_type: @adapter_type,
        provider_name: @config.provider,
        network_mode: @config.network_mode,
        ip_nw: @ip_nw,
        machines: build_machines,
        os_catalog: build_os_catalog,
        boot_timeout: @boot_timeout,
        box_check_update: @box_check_update,
        vbguest_auto_update: @vbguest_auto_update,
        runtime_options: @runtime_options
      )
    end

    private

    def build_machines
      @machine_groups.flat_map do |group|
        build_group(group)
      end
    end

    def build_group(group)
      count = group.fetch(:count).to_i
      return [] if count <= 0

      (1..count).map do |index|
        os_key = group.fetch(:os).to_sym
        os_info = @config.os_info(os_key)
        VagrantDomain::MachineSpec.new(
          name: format_name(group.fetch(:name), index),
          box: resolve_box(group, os_key),
          os_key: os_key,
          os_name: os_info.fetch(:os),
          resources: @resource_profiles.fetch(group.fetch(:resource_key).to_sym),
          network: VagrantDomain::NetworkSpec.new(
            ip: "#{@ip_nw}.#{group.fetch(:ip_start).to_i + index}",
            name: group.fetch(:network_name, @runtime_options.fetch(:docker_network_name, "")),
            ports: build_ports(group.fetch(:ports, []), index)
          ),
          files: build_files(group.fetch(:files, default_files_for(os_info.fetch(:os)))),
          metadata: group.fetch(:metadata, {})
        )
      end
    end

    def build_ports(ports, index)
      # Block form is LAZY — :host_base is only fetched when :host is absent.
      # The 2-arg form `fetch(:host, default)` evaluates `default` eagerly,
      # which fails when callers omit :host_base on purpose (single-VM groups
      # that want exact host ports).
      ports.map do |port|
        {
          guest: port.fetch(:guest),
          host: port.fetch(:host) { port.fetch(:host_base).to_i + index }
        }
      end
    end

    def build_files(files)
      files.map do |file|
        VagrantDomain::FileProvisionSpec.new(
          source: file.fetch(:source),
          destination: file.fetch(:destination)
        )
      end
    end

    def default_files_for(os_name)
      # Cosmetic dotfile copies (.tmux.conf, .vimrc). The Vagrant `file`
      # provisioner uses an SSH-over-net-ssh path that is known to deadlock
      # intermittently on macOS host + ed25519 key + VirtualBox guest. For
      # k3s scenarios these files aren't needed (Ansible runs from the
      # host and writes whatever it needs to).
      #
      # Set VAGRANT_INCLUDE_DOTFILES=1 to opt back in.
      return [] unless ENV["VAGRANT_INCLUDE_DOTFILES"] == "1"
      [
        { source: "./configuration/os/#{os_name}/.tmux.conf", destination: "$HOME/.tmux.conf" },
        { source: "./configuration/os/#{os_name}/.vimrc", destination: "$HOME/.vimrc" }
      ]
    end

    def resolve_box(group, os_key)
      return group.fetch(:box) if group.key?(:box)

      case os_key
      when :ubuntu
        @config.ubuntu_box(group.fetch(:box_version, :jammy_box))
      else
        @config.os_info(os_key).fetch(:box)
      end
    end

    def format_name(template, index)
      template.include?("%{index}") ? format(template, index: index) : template
    end

    def build_os_catalog
      {
        ubuntu: @config.os_info(:ubuntu),
        centos: @config.os_info(:centos),
        redhat: @config.os_info(:redhat)
      }
    end
  end
end
