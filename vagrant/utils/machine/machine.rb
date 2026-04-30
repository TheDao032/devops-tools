class Machine
  attr_accessor :config, :adapter, :machines, :provider, :network_mode

  def initialize(config, adapter, machines = [], provider, network_mode)
    @config = config
    @adapter = adapter
    @machines = machines
    @provider = provider
    @network_mode = network_mode
    @public_key = resolve_public_key
  end

  def resolve_public_key
    candidate = ENV["PUBLIC_KEY"]
    if candidate && !candidate.empty?
      expanded = File.expand_path(candidate)
      return expanded if File.exist?(expanded)
    end

    [
      "~/.ssh/id_ed25519.pub",
      "~/.ssh/id_rsa.pub"
    ].each do |path|
      expanded = File.expand_path(path)
      return expanded if File.exist?(expanded)
    end

    nil
  end

  def get_machine_status(vm_name)
    # machine_id_filepath = ".vagrant/machines/#{vm_name}/#{@provider}/id"
    # if not File.exist? machine_id_filepath
    #   return nil
    # else
    #   return File.read(machine_id_filepath)
    # end
    # Run the `vagrant status` command for the specific machine and capture its output
    status_output = %x(vagrant status #{vm_name} --machine-readable)
    # Check if the machine status includes "running"
    status_running = status_output.include?("state,running")
    puts "#{vm_name} is running: #{status_running}"

    return status_running
  end

  def all_machines_up
    @machines.each do |machine|
      unless get_machine_status(machine[:name])
        return false
      end
    end
    true
  end


  def trigger
    raise NotImplementedError, "Subclasses must implement the trigger method"
  end
end
