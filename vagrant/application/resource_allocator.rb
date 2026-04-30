require_relative "../domain/plan"

module VagrantApplication
  class ResourceAllocator
    def self.fixed(profiles)
      profiles.each_with_object({}) do |(role, resources), memo|
        memo[role.to_sym] = VagrantDomain::ResourceSpec.new(
          ram: resources.fetch(:ram),
          cpu: resources.fetch(:cpu)
        )
      end
    end

    def self.split(
      total_ram_gb:,
      total_cpu_cores:,
      servers:,
      agents:,
      server_ram_ratio:,
      server_cpu_ratio:,
      min_server_ram:,
      min_server_cpu:,
      min_agent_ram:,
      min_agent_cpu:
    )
      total_ram_mb = total_ram_gb * 1024
      server_count = safe_divisor(servers)
      agent_count = safe_divisor(agents)

      total_server_ram = total_ram_mb * server_ram_ratio
      total_server_cpu = total_cpu_cores * server_cpu_ratio
      remaining_ram = total_ram_mb - total_server_ram
      remaining_cpu = total_cpu_cores - total_server_cpu

      fixed(
        server: {
          ram: [(total_server_ram / server_count).to_i, min_server_ram].max,
          cpu: [(total_server_cpu / server_count).to_i, min_server_cpu].max
        },
        agent: {
          ram: [(remaining_ram / agent_count).to_i, min_agent_ram].max,
          cpu: [(remaining_cpu / agent_count).to_i, min_agent_cpu].max
        }
      )
    end

    def self.safe_divisor(count)
      value = count.to_i
      value.positive? ? value : 1
    end
    private_class_method :safe_divisor
  end
end
