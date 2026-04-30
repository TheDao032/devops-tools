# -*- mode: ruby -*-
# vi:set ft=ruby sw=2 ts=2 sts=2:

require_relative "../../utils/env"
require_relative "../../application/resource_allocator"
require_relative "../../application/cluster_plan_builder"
require_relative "../../infrastructure/vagrant_plan_applier"

virtualbox_config = VirtualboxConfig.new

resource_profiles = VagrantApplication::ResourceAllocator.split(
  total_ram_gb: 8,
  total_cpu_cores: 4,
  servers: virtualbox_config.num_servers,
  agents: virtualbox_config.num_agents,
  server_ram_ratio: 0.75,
  server_cpu_ratio: 0.5,
  min_server_ram: 2048,
  min_server_cpu: 2,
  min_agent_ram: 2048,
  min_agent_cpu: 1
)

plan = VagrantApplication::ClusterPlanBuilder.new(
  config: virtualbox_config,
  adapter_type: :virtualbox,
  ip_nw: virtualbox_config.ip_nw,
  resource_profiles: resource_profiles,
  machine_groups: [
    {
      count: virtualbox_config.num_servers,
      name: "puppet-server-%{index}",
      os: :ubuntu,
      box_version: :bionic_box,
      resource_key: :server,
      ip_start: 10,
      ports: [
        { guest: 80, host_base: 8080 },
        { guest: 443, host_base: 4430 }
      ]
    },
    {
      count: virtualbox_config.num_agents,
      name: "puppet-agent-%{index}",
      os: :ubuntu,
      box_version: :focal_box,
      resource_key: :agent,
      ip_start: 20,
      ports: [
        { guest: 80, host_base: 8090 },
        { guest: 443, host_base: 4440 }
      ]
    }
  ],
  box_check_update: false,
  vbguest_auto_update: false,
  runtime_options: {
    vbox_guest_disk: virtualbox_config.vbox_guest_disk
  }
).build

Vagrant.configure("2") do |config|
  VagrantInfrastructure::VagrantPlanApplier.new(config: config).apply(plan)
end
