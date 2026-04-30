# docker_mc.rb
require_relative 'machine'

class DockerMC < Machine
  def trigger
    if @network_mode == "NAT"
      # Trigger that fires after each VM starts.
      # Does nothing until all the VMs have started, at which point it
      # gathers the IP addresses assigned to the bridge interfaces by DHCP
      # and pushes a hosts file to each node with these IPs.
      @config.trigger.after :up do |trigger|
        trigger.name = "Post provisioner"
        trigger.ignore = [:destroy, :halt]
        trigger.ruby do |env, machine|
          if all_machines_up()
            puts "    Gathering IP addresses of containers..."
            machine_ips = []

            @machines.each do |machine|
              container_id = %x{docker ps --filter "name=#{machine[:name]}" --format "{{.ID}}"}.chomp
              next if container_id.empty?

              ip = %x{docker inspect -f '{{.NetworkSettings.Networks.#{machine[:network][:name]}.IPAddress}}' #{container_id}}.chomp
              next if ip.empty?

              machine_ips << [machine, ip]
            end

            hosts = machine_ips.map { |machine_spec, ip| "#{ip}  #{machine_spec[:name]}" }.join("\n")

            puts "    Setting /etc/hosts on containers..."
            File.open("hosts.tmp", "w") { |file| file.write(hosts) }
            machine_ips.each do |machine_spec, ip|
              machine = machine_spec
              container_id = %x{docker ps --filter "name=#{machine[:name]}" --format "{{.ID}}"}.chomp
              next if container_id.empty?

              system("docker cp hosts.tmp #{container_id}:/tmp/hosts.tmp")
              system("docker exec #{container_id} sh -c 'cat /tmp/hosts.tmp >> /etc/hosts'")

              if @public_key
                system("docker cp #{@public_key} #{container_id}:/tmp/id_rsa.pub")
                system("docker exec #{container_id} sh -c 'cat /tmp/id_rsa.pub >> /home/vagrant/.ssh/authorized_keys'")
              end

              system("docker exec #{container_id} sh -c 'echo \"nameserver 8.8.8.8\" >> /etc/resolv.conf'")
              system("docker exec #{container_id} sh -c 'echo \"nameserver 8.8.4.4\" >> /etc/resolv.conf'")
            end
            File.delete("hosts.tmp") if File.exist?("hosts.tmp")

            puts <<~EOF

                   VM build complete!

                   Use either of the following to access any NodePort services you create from your browser
                   replacing "port_number" with the number of your NodePort.

            EOF

            machine_ips.each do |machine_spec, ip|
              next if machine_spec[:network][:ports].empty?

              puts "  http://#{ip}:#{machine_spec[:network][:ports][0][:guest]}"
            end
            puts ""
          else
            puts "    Nothing to do here"
          end
        end
      end
    else
      @config.trigger.after :up do |trigger|
        trigger.name = "Post provisioner"
        trigger.ignore = [:destroy, :halt]
        trigger.ruby do |env, machine|
          if all_machines_up()
            puts "    Gathering IP addresses of containers..."
            @machines.each do |machine|
              container_id = %x{docker ps --filter "name=#{machine[:name]}" --format "{{.ID}}"}.chomp
              next if container_id.empty?

              if @public_key
                system("docker cp #{@public_key} #{container_id}:/tmp/id_rsa.pub")
                system("docker exec #{container_id} sh -c 'cat /tmp/id_rsa.pub >> /home/vagrant/.ssh/authorized_keys'")
              end

              system("docker exec #{container_id} sh -c 'echo \"nameserver 8.8.8.8\" >> /etc/resolv.conf'")
              system("docker exec #{container_id} sh -c 'echo \"nameserver 8.8.4.4\" >> /etc/resolv.conf'")
            end
            puts <<~EOF

                   VM build complete!

                   Use either of the following to access any NodePort services you create from your browser
                   replacing "port_number" with the number of your NodePort.

                 EOF
          else
            puts "    Nothing to do here"
          end
        end
      end
    end
  end
end
