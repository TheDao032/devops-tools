# -*- mode: ruby -*-
# vi:set ft=ruby sw=2 ts=2 sts=2:

require_relative "../../utils/env"
require_relative "../../application/resource_allocator"
require_relative "../../application/cluster_plan_builder"
require_relative "../../infrastructure/vagrant_plan_applier"

virtualbox_config = VirtualboxConfig.new

resource_profiles = VagrantApplication::ResourceAllocator.fixed(
  server: { ram: 2048, cpu: 2 },
  agent: { ram: 1024, cpu: 1 },
  infra: { ram: 1024, cpu: 1 }
)

plan = VagrantApplication::ClusterPlanBuilder.new(
  config: virtualbox_config,
  adapter_type: :virtualbox,
  ip_nw: virtualbox_config.ip_nw,
  resource_profiles: resource_profiles,
  machine_groups: [
    {
      count: 1,
      name: "server-1",
      os: :ubuntu,
      box_version: :jammy_box,
      resource_key: :server,
      ip_start: 10,
      ports: [
        { guest: 80, host_base: 8080 },
        { guest: 443, host_base: 4430 }
      ],
      metadata: {
        role: "primary"
      }
    },
    {
      count: 1,
      name: "server-2",
      os: :ubuntu,
      box_version: :jammy_box,
      resource_key: :server,
      ip_start: 11,
      ports: [
        { guest: 80, host_base: 8090 },
        { guest: 443, host_base: 4440 }
      ],
      metadata: {
        role: "sidecar"
      }
    },
    {
      count: 1,
      name: "agent-1",
      os: :ubuntu,
      box_version: :jammy_box,
      resource_key: :agent,
      ip_start: 20,
      metadata: {
        role: "agent"
      }
    },
    {
      count: 1,
      name: "infra-1",
      os: :ubuntu,
      box_version: :jammy_box,
      resource_key: :infra,
      ip_start: 30,
      ports: [
        { guest: 80, host_base: 8180 },
        { guest: 443, host_base: 4530 },
        { guest: 6443, host_base: 6443 }
      ],
      metadata: {
        role: "etcd-haproxy"
      }
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
