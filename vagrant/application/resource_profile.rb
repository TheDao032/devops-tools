require_relative "../domain/plan"
require_relative "./resource_allocator"

module VagrantApplication
  # ResourceProfile materializes a named profile (:low | :medium | :high) into
  # either a per-role hash of ResourceSpec values (for scenarios that hand-pick
  # resources per role) or a (ram_gb, cpu_cores) budget pair (for scenarios
  # that divide a budget dynamically via ResourceAllocator.split).
  #
  # Profile contents are intentionally collocated in the application layer so
  # the Vagrantfile composition root stays free of magic numbers, and the
  # contents can evolve without touching the domain or the CLI wrapper.
  #
  # Selection flow:
  #   ENV["RESOURCE_PROFILE"] -> Config#resource_profile -> ResourceProfile.{resolve,budget}
  #
  # Tenants MAY override the canonical mappings by implementing
  # `resource_profile_overrides(profile_name)` on their overrides class:
  #   - Returning a per-role hash → merged role-wise over CATALOG[name].
  #   - Returning { ram_gb:, cpu_cores: } → merged over BUDGETS[name].
  # Returning nil/empty falls through to the canonical mapping.
  module ResourceProfile
    # Per-role specs for `.fixed`-style callers (k3s.virtualbox).
    # RAM in MB, CPU in cores.
    #
    #   :low    — laptop dev / smoke test          (~3.5 GB / 4 vCPU total over 4 VMs)
    #   :medium — current Vagrantfile default      (~7   GB / 7 vCPU total over 4 VMs)
    #   :high   — load test / near-prod            (~14  GB / 14 vCPU total over 4 VMs)
    CATALOG = {
      low: {
        etcd:    { ram: 512,  cpu: 1 },
        server:  { ram: 1024, cpu: 1 },
        agent:   { ram: 1024, cpu: 1 }
      },
      medium: {
        etcd:    { ram: 1024, cpu: 1 },
        server:  { ram: 2048, cpu: 2 },
        agent:   { ram: 2048, cpu: 2 }
      },
      high: {
        etcd:    { ram: 2048, cpu: 2 },
        server:  { ram: 4096, cpu: 4 },
        agent:   { ram: 4096, cpu: 4 }
      }
    }.freeze

    # Total-budget pairs for `.split`-style callers (k3s.vmware_fusion, k8s,
    # docker-kubespray). The split() factory divides this between server/agent
    # roles according to per-scenario ratios; the profile only sets the cap.
    BUDGETS = {
      low:    { ram_gb: 4,  cpu_cores: 4  },
      medium: { ram_gb: 8,  cpu_cores: 4  },
      high:   { ram_gb: 16, cpu_cores: 8  }
    }.freeze

    KNOWN = CATALOG.keys.freeze
    DEFAULT = :medium

    # Resolve a per-role { role_sym => ResourceSpec } map for the named profile.
    # Used by scenarios that statically specify resources per role.
    def self.resolve(name, tenant_overrides: nil)
      key = normalize(name)

      base = CATALOG.fetch(key)
      merged = merge_per_role(base, tenant_overrides)
      ResourceAllocator.fixed(merged)
    end

    # Resolve a { ram_gb:, cpu_cores: } budget for the named profile.
    # Used by scenarios that call ResourceAllocator.split(...) and want the
    # division logic to stay in the scenario file (where ratios live).
    def self.budget(name, tenant_overrides: nil)
      key = normalize(name)

      base = BUDGETS.fetch(key)
      return base unless tenant_overrides.is_a?(Hash) && !tenant_overrides.empty?

      # Permissive merge: tenant can override either total_ram_gb/cpu_cores
      # under their canonical names, OR under shorthand :ram_gb/:cpu_cores.
      base.merge(
        ram_gb:    tenant_overrides[:ram_gb]    || base[:ram_gb],
        cpu_cores: tenant_overrides[:cpu_cores] || base[:cpu_cores]
      )
    end

    def self.describe(name)
      key = normalize(name)
      { name: key, per_role: CATALOG[key], budget: BUDGETS[key] }
    end

    def self.normalize(name)
      key = (name || DEFAULT).to_sym
      unless CATALOG.key?(key)
        raise ArgumentError,
              "Unknown RESOURCE_PROFILE='#{name}'. Known: #{KNOWN.join(', ')}"
      end
      key
    end
    private_class_method :normalize

    def self.merge_per_role(base, overrides)
      return base unless overrides.is_a?(Hash) && !overrides.empty?
      base.merge(overrides) do |_role, base_role, ovr_role|
        # Tenant-supplied role spec is partial — keep base keys it didn't touch.
        base_role.merge(ovr_role)
      end
    end
    private_class_method :merge_per_role
  end
end
