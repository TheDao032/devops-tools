# Vagrant Usage Guide

## Purpose
The Vagrant layer is now split into shared building blocks plus thin scenario entrypoints:

- `vagrant/domain/`: core plan objects such as machine, network, and cluster specs.
- `vagrant/application/`: shared plan builders and resource allocation logic.
- `vagrant/infrastructure/`: provider adapters that render plans into Vagrant DSL.
- `vagrant/vagrant-files/`: scenario files that declare what to build.

You should edit scenario intent in `vagrant/vagrant-files/`, not duplicate provider logic there.

## Available Scenarios
- `vagrant/vagrant-files/kubernetes/k3s.virtualbox.Vagrantfile`
- `vagrant/vagrant-files/kubernetes/k3s.vmware_fusion.Vagrantfile`
- `vagrant/vagrant-files/kubernetes/k8s.Vagrantfile`
- `vagrant/vagrant-files/kubernetes/docker-kubespray.Vagrantfile`
- `vagrant/vagrant-files/foreman/foreman.virtualbox.Vagrantfile`
- `vagrant/vagrant-files/foreman/foreman.v2.virtualbox.Vagrantfile`
- `vagrant/vagrant-files/foreman/foreman.v3.virtualbox.Vagrantfile`
- `vagrant/vagrant-files/grafana-alloy/grafana-alloy.virtualbox.Vagrantfile`
- `vagrant/vagrant-files/sentinel-one/agent.Vagrantfile`
- `vagrant/vagrant-files/psql/psql.Vagrantfile`

## Key Environment Variables
- `PROVIDER`: `virtualbox`, `vmware_fusion`, or `docker`
- `NETWORK_MODE`: usually `NAT` or `BRIDGE`
- `NUM_SERVERS`, `NUM_AGENTS`: scale values used by scenarios that read from config
- `ARCH`: optional override for box resolution, `arm64` or `amd64`
- `IP_NW`: optional network prefix override
- `VBOX_GUEST_DISK`: VirtualBox guest additions ISO path
- `RHEL_USERNAME`, `RHEL_PASSWORD`: required for RHEL-based scenarios

## Before You Run
From repo root:

```bash
ruby -c vagrant/utils/env.rb
ruby -c vagrant/vagrant-files/kubernetes/k3s.virtualbox.Vagrantfile
```

From `vagrant/`, select a scenario explicitly:

```bash
cd vagrant
VAGRANT_VAGRANTFILE=vagrant-files/kubernetes/k3s.virtualbox.Vagrantfile \
PROVIDER=virtualbox \
NETWORK_MODE=NAT \
NUM_SERVERS=2 \
NUM_AGENTS=1 \
vagrant status
```

## First Run Pattern
Example for VirtualBox `k3s`:

```bash
cd vagrant
VAGRANT_VAGRANTFILE=vagrant-files/kubernetes/k3s.virtualbox.Vagrantfile \
PROVIDER=virtualbox \
NETWORK_MODE=NAT \
NUM_SERVERS=2 \
NUM_AGENTS=1 \
VBOX_GUEST_DISK="/Applications/VirtualBox.app/Contents/MacOS/VBoxGuestAdditions.iso" \
vagrant up --provider virtualbox --provision
```

Example for VMware Fusion `k3s`:

```bash
cd vagrant
VAGRANT_VAGRANTFILE=vagrant-files/kubernetes/k3s.vmware_fusion.Vagrantfile \
PROVIDER=vmware_fusion \
NETWORK_MODE=NAT \
RHEL_USERNAME=... \
RHEL_PASSWORD=... \
vagrant up --provider vmware_fusion --provision
```

## How To Change a Scenario
- Change machine counts, ports, OS version, or IP offsets in the target `vagrant-files/...` scenario.
- Change shared sizing logic in `vagrant/application/resource_allocator.rb`.
- Change provider rendering in `vagrant/infrastructure/vagrant_plan_applier.rb`.
- Change box resolution in `vagrant/utils/env.rb`.

## Current Limits
- Syntax is validated, but provider boot paths are not fully runtime-verified yet.
- Legacy reference files under `vagrant/vagrant-files/common/` are not migrated.
