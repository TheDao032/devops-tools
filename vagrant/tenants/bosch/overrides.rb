# vagrant/tenants/bosch/overrides.rb
# Tenant overrides for Bosch. Defaults to Ubuntu 22.04, CIS Level 1, no FIPS.

require "rbconfig"

class BoschOverrides
  attr_reader :default_os, :default_ip_network, :compliance, :ssh_username

  # Vagrant Cloud-published baked box (see devops-tools/packer/docs/vagrant-cloud-publish.md).
  # Single box tag, multi-arch. Vagrant 2.4+ resolves the right artifact via
  # `--architecture <arch>` or the consumer-side `box_architecture`.
  BAKED_BOX_NAME = "bosch/ubuntu2204-cisl1".freeze

  def initialize
    @default_os         = :ubuntu
    @arch               = host_architecture
    @default_ip_network = ENV["IP_NW"] || "10.43.50"
    @ssh_username       = ENV["BOX_SSH_USER"] || "packer"  # baked box's first-boot user
    @compliance = {
      profile: "cis-l1",
      fips_mode: false,
      ssh_hardening: true
    }
  end

  # Returns the box reference appropriate for the host architecture.
  # Honors BOX_NAME env override (e.g. for testing a vanilla upstream box) and
  # BOX_FILE for a local on-disk .box (offline / pre-publish iteration).
  def default_box
    return ENV["BOX_NAME"] if ENV["BOX_NAME"] && !ENV["BOX_NAME"].empty?
    "#{BAKED_BOX_NAME}-#{@arch}"
  end

  # Optional: path to a local *.box file. When set, vagrant will resolve
  # `default_box` from this file rather than from Vagrant Cloud — useful for
  # smoke-testing a pre-publish artifact.
  #
  # Set with: BOX_FILE=/path/to/bosch-ubuntu2204-cisl1-arm64-<ver>.box
  def box_url
    ENV["BOX_FILE"]
  end

  # The chef/bento + Vagrant 2.4+ multi-arch convention: the consumer declares
  # which arch they want to pull. For single-arch boxes (only arm64 is baked
  # today), this still narrows the resolver.
  def box_architecture
    @arch.to_s
  end

  # Path to the SSH private key matching the public key baked into the box's
  # `authorized_keys` (cloud-init injects only the Packer build-time pubkey,
  # NOT Vagrant's standard insecure key — see http/user-data).
  #
  # Default: the in-repo Packer build-time keypair. Override with BOX_SSH_KEY
  # when running on a host that doesn't have the Packer keys directory.
  #
  # When this returns a real path:
  #   • Vagrantfile sets config.ssh.private_key_path to it
  #   • Vagrantfile sets config.ssh.insert_key = false
  #     (so Vagrant doesn't try to swap the baked-in key on first boot)
  #
  # Long-term fix: extend Packer's http/user-data template to ALSO include
  # Vagrant's well-known insecure public key in authorized-keys. After
  # re-baking, any consumer can vagrant up against the box without this
  # override.
  def ssh_private_key_path
    return ENV["BOX_SSH_KEY"] if ENV["BOX_SSH_KEY"] && !ENV["BOX_SSH_KEY"].empty?
    # vagrant/tenants/bosch/overrides.rb → ../../.. = devops-tools repo root
    File.expand_path("../../../packer/keys/packer_ed25519", __dir__)
  end

  def display
    puts "TENANT=bosch | os=#{@default_os} arch=#{@arch} box=#{default_box} ip_nw=#{@default_ip_network}"
    puts "  compliance: profile=#{@compliance[:profile]} fips=#{@compliance[:fips_mode]}"
    puts "  ssh_username=#{@ssh_username}"
    puts "  box_url=#{box_url}" if box_url
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

  # Hook for VagrantApplication::ResourceProfile.resolve / .budget.
  #
  # Per-role override (for .fixed-style scenarios like k3s.virtualbox):
  #   Return a partial hash keyed by role; missing keys/fields keep the
  #   catalog default. Example bumps server RAM under medium because the
  #   bosch box runs heavier audit/STIG scanners at first boot:
  #
  #     case profile_name.to_sym
  #     when :medium then { server: { ram: 3072 } }
  #     else nil
  #     end
  #
  # Budget override (for .split-style scenarios):
  #   Return { ram_gb:, cpu_cores: } (either or both). nil falls through.
  #
  # Returning nil leaves the canonical profile contents intact.
  def resource_profile_overrides(_profile_name)
    nil
  end

  private

  def host_architecture
    case RbConfig::CONFIG["host_cpu"].to_s.downcase
    when "arm64", "aarch64"
      "arm64"
    when "amd64", "x86_64"
      "amd64"
    else
      "amd64"
    end
  end
end
