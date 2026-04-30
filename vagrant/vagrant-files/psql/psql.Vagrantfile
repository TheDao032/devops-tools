# -*- mode: ruby -*-
# vi:set ft=ruby sw=2 ts=2 sts=2:

require_relative "../../utils/env"
require_relative "../../application/resource_allocator"
require_relative "../../application/cluster_plan_builder"
require_relative "../../infrastructure/vagrant_plan_applier"

docker_config = DockerConfig.new

resource_profiles = VagrantApplication::ResourceAllocator.split(
  total_ram_gb: 8,
  total_cpu_cores: 4,
  servers: 2,
  agents: 2,
  server_ram_ratio: 0.25,
  server_cpu_ratio: 0.25,
  min_server_ram: 2048,
  min_server_cpu: 2,
  min_agent_ram: 2048,
  min_agent_cpu: 1
)

plan = VagrantApplication::ClusterPlanBuilder.new(
  config: docker_config,
  adapter_type: :docker,
  ip_nw: "192.168.10",
  resource_profiles: resource_profiles,
  machine_groups: [
    {
      count: 2,
      name: "server-%{index}",
      os: :ubuntu,
      box_version: :jammy_box,
      resource_key: :server,
      ip_start: 10,
      network_name: docker_config.docker_network_name,
      ports: [{ guest: 22, host_base: 2730 }]
    },
    {
      count: 2,
      name: "agent-%{index}",
      os: :ubuntu,
      box_version: :jammy_box,
      resource_key: :agent,
      ip_start: 20,
      network_name: docker_config.docker_network_name,
      ports: [{ guest: 22, host_base: 2740 }]
    }
  ],
  box_check_update: false,
  vbguest_auto_update: false,
  runtime_options: {
    docker_network_name: docker_config.docker_network_name,
    docker_image: docker_config.docker_img
  }
).build

Vagrant.configure("2") do |config|
  VagrantInfrastructure::VagrantPlanApplier.new(config: config).apply(plan)
end
