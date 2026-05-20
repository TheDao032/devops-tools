# vagrant/tenants/renesas/overrides.rb
# Tenant overrides for Renesas. Mirrors the Ansible _company defaults so that
# Vagrant-provisioned dev VMs match what real hardware will run.

class RenesasOverrides
  attr_reader :default_os, :default_ip_network, :compliance, :default_box, :rhel_credentials

  def initialize
    @default_os         = :rhel
    @default_box        = "alvistack/rhel-9"
    @default_ip_network = ENV["IP_NW"] || "10.42.50"   # dev sandbox subnet (Vagrant-side)
    @compliance = {
      profile: "cis-l2",
      fips_mode: true,
      ssh_hardening: true
    }
    @rhel_credentials = {
      username: ENV["RHEL_USERNAME"] || raise("RHEL_USERNAME required for renesas tenant (RHEL subscription)"),
      password: ENV["RHEL_PASSWORD"] || raise("RHEL_PASSWORD required for renesas tenant (RHEL subscription)")
    }
  end

  def display
    puts "TENANT=renesas | os=#{@default_os} box=#{@default_box} ip_nw=#{@default_ip_network}"
    puts "  compliance: profile=#{@compliance[:profile]} fips=#{@compliance[:fips_mode]}"
  end

  # Hook for ansible provisioner: extra_vars to pass into compliance role.
  def ansible_extra_vars
    {
      "compliance" => {
        "profile"        => @compliance[:profile],
        "fips_mode"      => @compliance[:fips_mode],
        "ssh_hardening"  => @compliance[:ssh_hardening],
        "banner"         => "RENESAS — Authorized access only"
      }
    }
  end

  # Hook for VagrantApplication::ResourceProfile.resolve / .budget.
  # See bosch overrides for the contract. Renesas runs on real hardware in
  # production, so the dev cluster sizing here usually mirrors the catalog;
  # bump per-role values only for STIG/FIPS scenarios that need headroom.
  def resource_profile_overrides(_profile_name)
    nil
  end
end
