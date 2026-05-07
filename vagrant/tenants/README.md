# vagrant/tenants/

Per-company Vagrant overrides. Activated by exporting `TENANT=<name>` and
having the scenario Vagrantfile call `TenantOverrides.load`.

## Layout

```
tenants/
├── loader.rb            # entrypoint — TenantOverrides.load(config)
├── renesas/overrides.rb # RHEL 9, CIS-L2, FIPS, IP_NW=10.42.50
└── bosch/overrides.rb   # Ubuntu 22.04, CIS-L1, no FIPS, IP_NW=10.43.50
```

## How a scenario Vagrantfile uses this

```ruby
# vagrant-files/kubernetes/k3s.virtualbox.Vagrantfile
require_relative "../../tenants/loader"
tenant = TenantOverrides.load
tenant&.display

Vagrant.configure("2") do |config|
  # ...
  if tenant
    config.vm.box = tenant.default_box
    # IP_NW falls through to existing config classes (env.rb)
    # extra_vars get merged into the ansible provisioner block
    config.vm.provision "ansible" do |a|
      a.extra_vars = (a.extra_vars || {}).merge(tenant.ansible_extra_vars)
    end
  end
end
```

Without `TENANT` set, the loader returns `nil` and the scenario falls back to
the legacy `env.rb` defaults — preserves backwards compatibility for `local/`
and the original `dev/` scenarios.

## Why these knobs?

- **default_os / default_box**: Ansible inventories declare `os.default` per
  company. Vagrant should boot the same OS so dev VMs are realistic.
- **default_ip_network**: keeps Vagrant traffic in a tenant-owned IP range
  (10.42.50.0/24 for Renesas, 10.43.50.0/24 for Bosch). No collision with
  real on-prem ranges (10.42.10.0/24 for Renesas baremetal etc.).
- **compliance**: passed into the `compliance` Ansible role at provision
  time so the dev VM ends up at the same hardening level as prod hardware.
- **rhel_credentials** (Renesas only): RHEL subscription is per-company.
  Refusing to start without `RHEL_USERNAME`/`RHEL_PASSWORD` prevents
  accidental "fall back to dump_user" runs that would silently use an
  unsubscribed RHEL VM.
