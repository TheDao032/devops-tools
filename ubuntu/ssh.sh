#!/bin/bash

# Enable password auth in sshd so we can use ssh-copy-id
sed -i 's/#PasswordAuthentication/PasswordAuthentication/' /etc/ssh/sshd_config
sed -i 's/KbdInteractiveAuthentication no/KbdInteractiveAuthentication yes/' /etc/ssh/sshd_config
systemctl restart sshd

if [ ! -d /home/vagrant/.ssh ]
then
    mkdir /home/vagrant/.ssh
    chmod 700 /home/vagrant/.ssh
    chown vagrant:vagrant /home/vagrant/.ssh
fi

sh -c 'sudo apt-get update -y' &> /dev/null
sh -c 'sudo apt-get install -y sshpass' &> /dev/null
