# Use a base image with the desired OS (e.g., Ubuntu, Debian, etc.)
FROM ubuntu:22.04

# ARG AUTHORIZED_KEY
ARG VAGRANT_PASS

# Create an SSH user
RUN groupadd vagrant && \
		useradd -rm --create-home -s /bin/bash -g root -G sudo vagrant && \
		usermod -aG sudo vagrant && \
    echo "vagrant:${VAGRANT_PASS}" | chpasswd

# Allow SSH access
RUN mkdir -p /home/vagrant/.ssh && \
    chmod 700 /home/vagrant/.ssh && \
    touch /home/vagrant/.ssh/authorized_keys && \
    chmod 600 /home/vagrant/.ssh/authorized_keys && \
    # echo ${AUTHORIZED_KEY} > /home/vagrant/.ssh/authorized_keys && \
    chown -R vagrant /home/vagrant/.ssh

# Configure SSH
# Install SSH server and dependencies
RUN apt-get update && apt-get install -y openssh-server sudo vim iproute2 --fix-missing && \
    apt-get autoremove && \
    rm -rf /var/lib/apt/lists/*

RUN echo 'vagrant ALL=(ALL) NOPASSWD: ALL' >> /etc/sudoers.d/vagrant && \
    chmod 0440 /etc/sudoers.d/vagrant && \
		sed -i -e 's/Defaults.*requiretty/#&/' /etc/sudoers

# Configure SSHD
RUN mkdir /var/run/sshd
# Generate SSH host keys
RUN ssh-keygen -A

# Start SSH server on container startup
RUN /usr/sbin/sshd -D &> /dev/null

# Expose the SSH port
EXPOSE 22 5432

ENTRYPOINT ["/lib/systemd/systemd"]
