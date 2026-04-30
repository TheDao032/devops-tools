# Vagrant Clean Architecture Tracker

## Goal
Refactor `vagrant/` so the core infrastructure intent is expressed as reusable plans and specs, while provider-specific Vagrant DSL stays in adapter code.

## Target Layers
- `vagrant/domain`: machine, network, and cluster plan objects.
- `vagrant/application`: resource allocation and plan building use cases.
- `vagrant/infrastructure`: Vagrant adapters, provider mappings, and post-up machine controllers.
- `vagrant/vagrant-files`: thin entrypoints that describe scenarios and delegate rendering.

## Migration Checklist
- [x] Add domain plan objects.
- [x] Add shared resource allocation and cluster plan builders.
- [x] Add a Vagrant plan applier for provider-specific rendering.
- [x] Migrate all active Vagrantfiles to use the shared plan layer.
- [x] Fix machine-controller runtime defects across VirtualBox, VMware Fusion, and Docker.
- [x] Re-run Ruby syntax validation across the refactored files.

## Current Risks
- Provider boot paths are not runtime-verified yet with `vagrant up`.
- Legacy reference files under `vagrant/vagrant-files/common/` are still outside the shared plan layer.
- Existing local workspace changes in `vagrant/` should be preserved while the refactor lands.

## Validation
- Minimum bar: `ruby -c` passes for every migrated Vagrantfile and the new shared layer.
- Follow-up: run representative `vagrant up` flows for `k3s.virtualbox`, `k3s.vmware_fusion`, and `psql`.

## Landed in This Pass
- Added shared plan objects in `vagrant/domain/plan.rb`.
- Added resource allocation and plan building in `vagrant/application/`.
- Added provider-aware rendering in `vagrant/infrastructure/vagrant_plan_applier.rb`.
- Migrated active scenario files in `vagrant/vagrant-files/` to declarative plan definitions.
- Fixed controller bugs in `virtualbox_mc.rb`, `vmware_fusion_mc.rb`, and `docker_mc.rb`.
