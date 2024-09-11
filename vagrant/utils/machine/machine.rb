class Machine
  attr_accessor :config, :adapter, :machines, :provider, :network_mode

  def initialize(config, adapter, machines = [], provider, network_mode)
    @config = config
    @adapter = adapter
    @machines = machines
    @provider = provider
    @network_mode = network_mode
  end

  def get_machine_id(vm_name)
    machine_id_filepath = ".vagrant/machines/#{vm_name}/#{@provider}/id"
    if not File.exist? machine_id_filepath
      return nil
    else
      return File.read(machine_id_filepath)
    end
  end

  def all_machines_up
    @machines.each do |machine|
      if get_machine_id(machine[:name]).nil?
        return false
      end
    end
    true
  end


  def trigger
    raise NotImplementedError, "Subclasses must implement the trigger method"
  end
end
