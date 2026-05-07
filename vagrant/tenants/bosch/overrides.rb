# vagrant/tenants/bosch/overrides.rb
# Tenant overrides for Bosch. Defaults to Ubuntu 22.04, CIS Level 1, no FIPS.

class BoschOverrides
  attr_reader :default_os, :default_ip_network, :compliance, :default_box

  def initialize
    @default_os         = :ubuntu
    @default_box        = "ubuntu/jammy64"   # amd64; arm64 hosts use bento/ubuntu-22.04
    @default_ip_network = ENV["IP_NW"] || "10.43.50"
    @compliance = {
      profile: "cis-l1",
      fips_mode: false,
      ssh_hardening: true
    }
  end

  def display
    puts "TENANT=bosch | os=#{@default_os} box=#{@default_box} ip_nw=#{@default_ip_network}"
    puts "  compliance: profile=#{@compliance[:profile]} fips=#{@compliance[:fips_mode]}"
  end

  def ansible_extra_vars
    {
      "compliance" => {
        "profile"        => @compliance[:profile],
        "fips_mode"      => @compliance[:fips_mode],
        "ssh_hardening"  => @compliance[:ssh_hardening],
        "banner"         => "BOSCH — Authorized access only"
      }
    }
  end
end
