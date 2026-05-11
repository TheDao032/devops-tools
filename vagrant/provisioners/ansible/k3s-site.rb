# vagrant/provisioners/ansible/k3s-site.rb
#
# Attaches the k3s Ansible provisioner to a ClusterPlan. Designed to run
# AFTER all VMs in the plan are up, so kube-apiserver / HAProxy can see all
# nodes during install.
#
# Usage in a scenario Vagrantfile:
#
#   require_relative "../../provisioners/ansible/k3s-site"
#
#   Vagrant.configure("2") do |config|
#     VagrantInfrastructure::VagrantPlanApplier.new(config: config).apply(plan)
#     K3sAnsibleSite.attach(
#       config:    config,
#       plan:      plan,
#       tenant:    tenant,                 # may be nil
#       playbook:  "ansible/playbooks/k3s-playbooks/vagrant-bosch-site.yml",
#       inventory: "ansible/inventories/local/k3s/virtualbox-bosch"
#     )
#   end
#
# Mechanics: re-opens the LAST VM's `config.vm.define` block and attaches a
# `node.vm.provision "ansible"` step with `limit = "all"`. Vagrant fires the
# provisioner exactly once, against every machine in the plan.

module K3sAnsibleSite
  module_function

  # Convention: machines tagged with these roles map into these Ansible groups.
  ROLE_TO_GROUP = {
    "server-haproxy" => %w[server infra],
    "server"         => %w[server],
    "infra"          => %w[infra],
    "agent"          => %w[agent],
    "etcd"           => %w[etcd]
  }.freeze

  def attach(config:, plan:, tenant: nil, playbook:, inventory: nil)
    last_machine = plan.machines.last
    raise "K3sAnsibleSite.attach: plan has no machines" unless last_machine

    groups     = build_groups(plan)
    extra_vars = build_extra_vars(plan, tenant)

    config.vm.define last_machine.name do |node|
      node.vm.provision "ansible" do |ansible|
        ansible.playbook       = playbook
        ansible.limit          = "all"
        ansible.groups         = groups
        ansible.extra_vars     = extra_vars
        ansible.inventory_path = inventory if inventory
        ansible.compatibility_mode = "2.0"
        # Surface task names but not full per-task verbose output. Bump to "vv"
        # or "vvv" via env var when debugging a specific role.
        verbosity = ENV["ANSIBLE_VERBOSITY"]
        ansible.verbose = verbosity if verbosity && !verbosity.empty?
      end
    end
  end

  # Build the groups hash Vagrant's ansible provisioner expects:
  #   { "server" => ["server-1"], "agent" => ["agent-1", "agent-2"], ... }
  # Multi-group machines (e.g. server-1 with role "server-haproxy") appear in
  # every relevant group. Unknown roles are quietly skipped — log to stderr.
  def build_groups(plan)
    groups = Hash.new { |h, k| h[k] = [] }
    plan.machines.each do |m|
      role = (m.metadata[:role] || m.metadata["role"]).to_s
      mapped = ROLE_TO_GROUP[role]
      if mapped.nil?
        warn "K3sAnsibleSite: machine #{m.name} has unknown role '#{role}', skipping"
        next
      end
      mapped.each { |g| groups[g] << m.name }
    end
    groups.each { |_, names| names.uniq! }
    groups.transform_keys(&:to_s).transform_values(&:freeze)
  end

  def build_extra_vars(plan, tenant)
    base = {
      "ansible_user" => (plan.runtime_options[:ssh_user] || "vagrant"),
      "tenant"       => (ENV["TENANT"] || "default")
    }
    base.merge!(tenant.ansible_extra_vars) if tenant && tenant.respond_to?(:ansible_extra_vars)
    base
  end
end
