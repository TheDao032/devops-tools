require_relative "../providers/docker/docker"
require_relative "../providers/virtualbox/centos"
require_relative "../providers/virtualbox/rhel"
require_relative "../providers/virtualbox/ubuntu"
require_relative "../providers/vmware_fusion/rhel"
require_relative "../providers/vmware_fusion/ubuntu"
require_relative "../utils/machine/docker_mc"
require_relative "../utils/machine/virtualbox_mc"
require_relative "../utils/machine/vmware_fusion_mc"

module VagrantInfrastructure
  class VagrantPlanApplier
    VM_CLASSES = {
      virtualbox: {
        ubuntu: UbuntuVMVirtualbox,
        centos: CentosVMVirtualbox,
        redhat: RhelVMVirtualbox
      },
      vmware_fusion: {
        ubuntu: UbuntuVMFusion,
        redhat: RhelVMFusion
      }
    }.freeze

    CONTROLLER_CLASSES = {
      virtualbox: VirtualBoxMC,
      vmware_fusion: VMWareFusionMC,
      docker: DockerMC
    }.freeze

    def initialize(config:)
      @config = config
    end

    def apply(plan)
      configure_runtime(plan)

      legacy_machines = plan.legacy_machines
      plan.machines.each do |machine|
        define_machine(plan, machine, legacy_machines)
      end

      build_controller(plan, legacy_machines).trigger
    end

    private

    def configure_runtime(plan)
      @config.vm.boot_timeout = plan.boot_timeout
      @config.vm.box_check_update = plan.box_check_update

      begin
        @config.vbguest.auto_update = plan.vbguest_auto_update
      rescue NoMethodError
        nil
      end

      default_box = plan.runtime_options[:default_box]
      @config.vm.box = default_box if default_box
    end

    def define_machine(plan, machine, legacy_machines)
      if plan.adapter_type == :docker
        build_docker_vm(plan, machine).define
        return
      end

      build_vm(plan, machine).define(
        machine.os_name,
        plan.ip_nw,
        legacy_machines,
        plan.os_catalog.fetch(machine.os_key)
      )
    end

    def build_vm(plan, machine)
      klass = VM_CLASSES.fetch(plan.adapter_type).fetch(machine.os_key)

      case plan.adapter_type
      when :virtualbox
        klass.new(
          machine.box,
          @config,
          machine.name,
          machine.name,
          machine.network.ip,
          plan.network_mode,
          plan.runtime_options.fetch(:vbox_guest_disk),
          machine.network.ports,
          machine.files.map(&:to_h),
          machine.resources.ram,
          machine.resources.cpu
        )
      when :vmware_fusion
        klass.new(
          machine.box,
          @config,
          machine.name,
          machine.name,
          machine.network.ip,
          plan.network_mode,
          machine.network.ports,
          machine.files.map(&:to_h),
          machine.resources.ram,
          machine.resources.cpu
        )
      end
    end

    def build_docker_vm(plan, machine)
      DockerVM.new(
        machine.box,
        @config,
        machine.name,
        machine.name,
        machine.network.ip,
        plan.runtime_options.fetch(:docker_network_name),
        plan.network_mode,
        machine.network.ports,
        plan.runtime_options.fetch(:docker_volumes, []),
        { "DOCKER_IMG" => plan.runtime_options.fetch(:docker_image) },
        machine.files.map(&:to_h),
        plan.runtime_options.fetch(:docker_create_args, [])
      )
    end

    def build_controller(plan, legacy_machines)
      CONTROLLER_CLASSES.fetch(plan.adapter_type).new(
        @config,
        "",
        legacy_machines,
        plan.provider_name,
        plan.network_mode
      )
    end
  end
end
