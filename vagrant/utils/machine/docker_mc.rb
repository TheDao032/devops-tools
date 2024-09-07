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
            ips = []

            @machines.each do |machine|
              container_id = %x{docker ps --filter "name=#{machine[:name]}" --format "{{.ID}}"}.chomp
              container_ids.push(container_id)
              ip = %x{docker inspect -f '{{.NetworkSettings.Networks.#{machine[:network][:name]}.IPAddress}}' #{container_id}}.chomp
              ips.push(ip)
            end

            hosts = ""
            ips.each_with_index do |ip, i|
              hosts << ip << "  " << @machines[i][:name] << "\n"
            end

            # Output and set /etc/hosts on each container

            puts "    Setting /etc/hosts on containers..."
            container_id = %x{docker ps --filter "name=#{machine.name}" --format "{{.ID}}"}.chomp
            if File.exist?("hosts.tmp.#{machine.name}")
              system("docker cp hosts.tmp.#{machine.name} #{container_id}:/tmp/hosts.tmp")
              system("docker exec #{container_id} sh -c 'cat /tmp/hosts.tmp | sudo tee -a /etc/hosts'")
            else
              puts "hosts.tmp file not found, skipping container #{container_id}."
            end

            puts "    Setting authorized_keys on containers..."
            system("docker cp ~/.ssh/id_rsa.pub #{container_id}:/tmp/id_rsa.pub")
            system("docker exec #{container_id} sh -c 'cat /tmp/id_rsa.pub >> /home/vagrant/.ssh/authorized_keys'")

            system("docker exec #{container_id} sh -c 'echo \"nameserver 8.8.8.8\" >> /etc/resolv.conf'")
            system("docker exec #{container_id} sh -c 'echo \"nameserver 8.8.4.4\" >> /etc/resolv.conf'")
            # end

            # Clean up
            if File.exist?("hosts.tmp.#{machine.name}")
              File.delete("hosts.tmp.#{machine.name}")
              puts "hosts.tmp.#{machine.name} file deleted successfully."
            else
              puts "hosts.tmp.#{machine.name} file not found during cleanup."
            end

            puts <<~EOF

                   VM build complete!

                   Use either of the following to access any NodePort services you create from your browser
                   replacing "port_number" with the number of your NodePort.

            EOF

            (1..ips.length).each do |i|
              puts "  http://#{ips[i]}:#{@machines[i][:ports][0]}"
            end
            puts ""
          else
            puts "    Nothing to do here"
          end
        end
      end
    else
      config.trigger.after :up do |trigger|
        trigger.name = "Post provisioner"
        trigger.ignore = [:destroy, :halt]
        trigger.ruby do |env, machine|
          if all_machines_up()
            puts "    Gathering IP addresses of containers..."

            container_id = %x{docker ps --filter "name=#{machine.name}" --format "{{.ID}}"}.chomp
            system("docker cp ~/.ssh/id_rsa.pub #{container_id}:/tmp/id_rsa.pub")
            system("docker exec #{container_id} sh -c 'cat /tmp/id_rsa.pub >> /home/vagrant/.ssh/authorized_keys'")

            system("docker exec #{container_id} sh -c 'echo \"nameserver 8.8.8.8\" >> /etc/resolv.conf'")
            system("docker exec #{container_id} sh -c 'echo \"nameserver 8.8.4.4\" >> /etc/resolv.conf'")
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
