# -*- mode: ruby -*-
# vi:set ft=ruby sw=2 ts=2 sts=2:

require_relative "../../utils/env"
require_relative "../../application/resource_allocator"
require_relative "../../application/resource_profile"
require_relative "../../application/cluster_plan_builder"
require_relative "../../infrastructure/vagrant_plan_applier"

vmware_config = VMWareFusionConfig.new

# Profile-driven budget — RESOURCE_PROFILE env (low|medium|high) selects the
# total ram/cpu pool; the .split() factory below divides it across server/agent
# roles using scenario-specific ratios. Default :medium matches the previous
# hardcoded 8 GB / 4 cores.
budget = VagrantApplication::ResourceProfile.budget(vmware_config.resource_profile)

resource_profiles = VagrantApplication::ResourceAllocator.split(
  total_ram_gb: budget[:ram_gb],
  total_cpu_cores: budget[:cpu_cores],
  servers: vmware_config.num_servers,
  agents: vmware_config.num_agents,
  server_ram_ratio: 0.25,
  server_cpu_ratio: 0.25,
  min_server_ram: 2048,
  min_server_cpu: 2,
  min_agent_ram: 2048,
  min_agent_cpu: 1
)

plan = VagrantApplication::ClusterPlanBuilder.new(
  config: vmware_config,
  adapter_type: :vmware_fusion,
  ip_nw: vmware_config.ip_nw,
  resource_profiles: resource_profiles,
  machine_groups: [
    {
      count: vmware_config.num_servers,
      name: "server-%{index}",
      os: :redhat,
      resource_key: :server,
      ip_start: 10,
      ports: [{ guest: 22, host_base: 2730 }]
    },
    {
      count: vmware_config.num_agents,
      name: "agent-%{index}",
      os: :redhat,
      resource_key: :agent,
      ip_start: 20,
      ports: [{ guest: 22, host_base: 2740 }]
    }
  ],
  box_check_update: false,
  vbguest_auto_update: false
).build

Vagrant.configure("2") do |config|
  VagrantInfrastructure::VagrantPlanApplier.new(config: config).apply(plan)
end
