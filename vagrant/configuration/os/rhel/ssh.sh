#!/bin/bash
set -e
RHEL_USERNAME=$1
RHEL_PASSWORD=$2


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

sh -c "sudo subscription-manager register --username ${RHEL_USERNAME} --password ${RHEL_PASSWORD} --auto-attach"
# sh -c "sudo subscription-manager release --set=9.5"
sh -c "sudo dnf config-manager --set-disabled home_alvistack"
sh -c 'sudo yum update -y && sudo yum install sshpass -y' > /dev/null 2>&1 &

exit 0
