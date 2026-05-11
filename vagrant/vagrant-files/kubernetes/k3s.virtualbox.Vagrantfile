# -*- mode: ruby -*-
# vi:set ft=ruby sw=2 ts=2 sts=2:
#
# k3s cluster on VirtualBox — 4-VM topology
# ------------------------------------------
#   etcd-1     : standalone external etcd datastore for k3s
#   server-1   : k3s server + HAProxy load-balancer (single ingress point)
#   agent-1    : k3s agent
#   agent-2    : k3s agent
#
# Tenancy:
#   TENANT=bosch  → uses the Packer-baked Vagrant box `bosch/ubuntu2204-cisl1-<arch>`
#                   (see devops-tools/packer/docs/vagrant-cloud-publish.md)
#                   IP network defaults to 10.43.50.0/24 (per bosch overrides)
#                   Compliance profile injected into Ansible: cis-l1, no FIPS
#   TENANT unset  → falls back to legacy env.rb defaults (vanilla Ubuntu boxes)
#
# Quick start:
#   cd vagrant
#   TENANT=bosch PROVIDER=virtualbox \
#     VAGRANT_VAGRANTFILE=vagrant-files/kubernetes/k3s.virtualbox.Vagrantfile \
#     vagrant up --provider virtualbox
#
# Pre-publish smoke test (use a local *.box file instead of Vagrant Cloud):
#   BOX_FILE=/path/to/output/bosch/arm64/virtualbox/<ver>/*.box  TENANT=bosch ...

require_relative "../../utils/env"
require_relative "../../application/resource_allocator"
require_relative "../../application/cluster_plan_builder"
require_relative "../../infrastructure/vagrant_plan_applier"
require_relative "../../tenants/loader"
require_relative "../../provisioners/ansible/k3s-site"

virtualbox_config = VirtualboxConfig.new
tenant            = TenantOverrides.load
tenant&.display

# Resolve the Vagrant box to boot. Tenant override wins; falls back to env.rb
# catalog (e.g. ubuntu/jammy64 amd64, bento/ubuntu-22.04 arm64).
box_name      = tenant&.default_box || virtualbox_config.ubuntu_box(:jammy_box)
box_file_url  = tenant.respond_to?(:box_url) ? tenant.box_url : nil
ssh_user_over = tenant&.ssh_username
ssh_priv_key  = tenant.respond_to?(:ssh_private_key_path) ? tenant.ssh_private_key_path : nil

# Tenant IP network override (e.g. bosch → 10.43.50). Falls through to the
# config-class default (192.168.56) when TENANT is unset.
ip_nw = (tenant && tenant.default_ip_network) || virtualbox_config.ip_nw

# Resource profiles per machine role.
resource_profiles = VagrantApplication::ResourceAllocator.fixed(
  etcd:    { ram: 1024, cpu: 1 },
  server:  { ram: 2048, cpu: 2 },
  agent:   { ram: 2048, cpu: 2 }
)

# 4-VM topology — one machine_group entry per role for clarity.
# IP-suffix layout under <ip_nw>.x:
#   .10   server-1 (k3s server + HAProxy)
#   .20   agent-1
#   .21   agent-2
#   .30   etcd-1
machine_groups = [
  {
    count: 1,
    name: "etcd-1",
    os: :ubuntu,
    box: box_name,
    resource_key: :etcd,
    ip_start: 29,                     # +1 → 30
    metadata: {
      role:   "etcd",
      tenant: ENV["TENANT"] || "default"
    }
  },
  {
    count: 1,
    name: "server-1",
    os: :ubuntu,
    box: box_name,
    resource_key: :server,
    ip_start: 9,                      # +1 → 10
    # Use `host:` (exact) rather than `host_base:` (which adds VM index).
    # Single-VM group → no index math wanted.
    ports: [
      { guest: 80,   host: 8080 },   # ingress http
      { guest: 443,  host: 4430 },   # ingress https
      { guest: 6443, host: 6443 },   # kube-apiserver (direct, when not going through HAProxy)
      { guest: 6445, host: 6445 }    # HAProxy front for kube-apiserver
    ],
    metadata: {
      role:    "server-haproxy",          # k3s server + HAProxy load-balancer
      tenant:  ENV["TENANT"] || "default"
    }
  },
  {
    count: 1,
    name: "agent-1",
    os: :ubuntu,
    box: box_name,
    resource_key: :agent,
    ip_start: 19,                     # +1 → 20
    metadata: {
      role:   "agent",
      tenant: ENV["TENANT"] || "default"
    }
  },
  {
    count: 1,
    name: "agent-2",
    os: :ubuntu,
    box: box_name,
    resource_key: :agent,
    ip_start: 20,                     # +1 → 21
    metadata: {
      role:   "agent",
      tenant: ENV["TENANT"] || "default"
    }
  }
]

plan = VagrantApplication::ClusterPlanBuilder.new(
  config: virtualbox_config,
  adapter_type: :virtualbox,
  ip_nw: ip_nw,
  resource_profiles: resource_profiles,
  machine_groups: machine_groups,
  box_check_update: false,
  vbguest_auto_update: false,
  runtime_options: {
    vbox_guest_disk: virtualbox_config.vbox_guest_disk,
    box_file_url:    box_file_url,        # set when BOX_FILE points at a local artifact
    ssh_user:        ssh_user_over,       # baked box's first-boot user (e.g. "packer")
    box_arch:        tenant&.box_architecture
  }
).build

Vagrant.configure("2") do |config|
  # Pre-publish / offline: instruct vagrant to resolve `box_name` from a local
  # .box file rather than Vagrant Cloud.
  if box_file_url && !box_file_url.empty?
    config.vm.box_url = "file://#{box_file_url}"
  end

  # The Packer-baked box ships with a `packer` user. Override the default
  # vagrant SSH user so `vagrant up` can complete its first-boot handshake.
  config.ssh.username = ssh_user_over if ssh_user_over

  # The baked box does NOT include VirtualBox Guest Additions (vboxsf kernel
  # module). On arm64 VirtualBox 7 / Apple Silicon, Guest Additions isn't
  # reliably available anyway. Vagrant's default `/vagrant` shared-folder
  # auto-mount needs vboxsf, so it would fail with
  # "unknown filesystem type 'vboxsf'".
  #
  # We don't need /vagrant inside the guest — Ansible runs from the host over
  # SSH and never reads from /vagrant. Disable the auto-mount.
  config.vm.synced_folder ".", "/vagrant", disabled: true

  # The baked box's authorized_keys contains only the Packer build-time
  # public key, not Vagrant's well-known insecure key. Point Vagrant at the
  # matching private key and disable the first-boot key replacement (which
  # would try to authenticate with the insecure key first → fail loop).
  if ssh_priv_key && File.exist?(ssh_priv_key)
    config.ssh.private_key_path = ssh_priv_key
    config.ssh.insert_key       = false
  elsif ssh_priv_key
    warn "WARN: tenant.ssh_private_key_path = #{ssh_priv_key} does not exist; " \
         "falling back to Vagrant's default insecure key (likely to fail with " \
         "this box). Set BOX_SSH_KEY=/path/to/key or re-bake with the cloud-init " \
         "template that includes Vagrant's insecure pubkey."
  end

  # Multi-arch box resolution (Vagrant 2.4+). Harmless on older Vagrant.
  if tenant&.box_architecture
    begin
      config.vm.box_architecture = tenant.box_architecture
    rescue NoMethodError
      # vagrant < 2.4 — silently skip; the box's metadata.json will still
      # influence resolution if it declares a single architecture.
    end
  end

  VagrantInfrastructure::VagrantPlanApplier.new(config: config).apply(plan)

  # Wire the Ansible provisioner against the LAST VM in the plan, with
  # `limit: all`. Vagrant fires the playbook exactly once, after every VM
  # is up — so the playbook sees the full inventory (server, agents, etcd).
  #
  # Override path with PLAYBOOK / INVENTORY env vars for ad-hoc testing.
  K3sAnsibleSite.attach(
    config:    config,
    plan:      plan,
    tenant:    tenant,
    playbook:  ENV["PLAYBOOK"]  || "ansible/playbooks/k3s-playbooks/vagrant-bosch-site.yml",
    inventory: ENV["INVENTORY"] || "ansible/inventories/local/k3s/virtualbox-bosch"
  )
end
