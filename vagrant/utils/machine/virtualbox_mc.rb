
require_relative 'machine'

class VirtualBoxMC < Machine
  def trigger
    if @network_mode == "BRIDGE"
      # Trigger that fires after each VM starts.
      # Does nothing until all the VMs have started, at which point it
      # gathers the IP addresses assigned to the bridge interfaces by DHCP
      # and pushes a hosts file to each node with these IPs.
      @config.trigger.after :up do |trigger|
        trigger.name = "Post provisioner"
        trigger.ignore = [:destroy, :halt]
        trigger.ruby do |env, machine|
          if all_machines_up()
            puts "    Gathering IP addresses of clusters..."
            ips = []

            @machines.each do |machine|
              ips.push(%x{vagrant ssh #{machine[:name]} -c 'public-ip'}.chomp)
            end

            hosts = ""
            ips.each_with_index do |ip, i|
              hosts << ip << "  " << @machines[i][:name] << "\n"
            end

            puts "    Setting /etc/hosts on clusters..."
            File.open("hosts.tmp", "w") { |file| file.write(hosts) }

            @machines.each do |machine|
              if get_machine_status(machine[:name])
                system("vagrant upload hosts.tmp /tmp/hosts.tmp #{machine[:name]}")
                system("vagrant ssh #{machine[:name]} -c 'cat /tmp/hosts.tmp | sudo tee -a /etc/hosts'")
                system("vagrant upload ~/.ssh/id_rsa.pub /tmp/id_rsa.pub #{machine[:name]}")
                system("vagrant ssh #{machine[:name]} -c 'cat /tmp/id_rsa.pub >> /home/vagrant/.ssh/authorized_keys'")
              end
            end

            File.delete("hosts.tmp")
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
            puts "    Gathering IP addresses of clusters..."
            @machines.each do |machine|
              system("vagrant upload ~/.ssh/id_rsa.pub /tmp/id_rsa.pub #{machine[:name]}")
              system("vagrant ssh #{machine[:name]} -c 'cat /tmp/id_rsa.pub >> /home/vagrant/.ssh/authorized_keys'")
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
