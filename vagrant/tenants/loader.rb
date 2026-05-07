# vagrant/tenants/loader.rb — opt-in tenant override loader.
#
# Scenario Vagrantfiles can require this file to apply per-tenant defaults
# (default OS, IP network, RHEL credentials, hardening flags). Reads the
# TENANT env var. No-op if TENANT is unset (preserves the legacy behaviour
# for the local/dev scenarios that don't care about tenancy).
#
# Usage in a scenario Vagrantfile:
#
#   require_relative "../../tenants/loader"
#   tenant_overrides = TenantOverrides.load(config)   # or nil if unset
#
# The override module exposes:
#   .default_os          -> :ubuntu | :rhel | :centos
#   .default_ip_network  -> "10.42.50" (etc.)
#   .compliance          -> { profile:, fips_mode: }

module TenantOverrides
  KNOWN = %w[renesas bosch].freeze

  def self.load(_vagrant_config = nil)
    tenant = ENV["TENANT"]
    return nil if tenant.nil? || tenant.empty?

    unless KNOWN.include?(tenant)
      raise ArgumentError, "Unknown TENANT='#{tenant}'. Known: #{KNOWN.join(', ')}"
    end

    path = File.expand_path("./#{tenant}/overrides.rb", __dir__)
    raise LoadError, "TenantOverrides: missing #{path}" unless File.exist?(path)

    require path
    klass = Object.const_get("#{tenant.capitalize}Overrides")
    klass.new
  end
end
