# Use a base image with the desired OS (e.g., Ubuntu, Debian, etc.)
FROM ubuntu:latest

ARG AUTHORIZED_KEY
ARG VAGRANT_PASS

# Create an SSH user
RUN useradd -rm --create-home -s /bin/bash -g root -G sudo vagrant && \
    echo "vagrant:${VAGRANT_PASS}" | chpasswd
# Allow SSH access
RUN mkdir -p /home/vagrant/.ssh && \
    chmod 700 /home/vagrant/.ssh && \
    touch /home/vagrant/.ssh/authorized_keys && \
    chmod 600 /home/vagrant/.ssh/authorized_keys && \
    echo ${AUTHORIZED_KEY} > /home/vagrant/.ssh/authorized_keys && \
    chown -R vagrant /home/vagrant/.ssh

# Install SSH server and dependencies
RUN apt-get update && apt-get install -y openssh-server sudo pipx --fix-missing && \
    apt-get autoremove && \
    rm -rf /var/lib/apt/lists/*
RUN echo 'vagrant ALL = NOPASSWD: ALL' > /etc/sudoers
RUN sed -i -e 's/Defaults.*requiretty/#&/' /etc/sudoers
# RUN sed -i -e 's/\(UsePAM \)yes/\1 no/' /etc/ssh/sshd_config
RUN mkdir /var/run/sshd

# Using vagrant user
USER vagrant
WORKDIR /home/vagrant

# Install ansible
# RUN pipx ensurepath && pipx install --include-deps ansible
# RUN sudo ln -s /home/vagrant/.local/bin/ansible /usr/bin/ansible

USER root
# Generate SSH host keys
RUN ssh-keygen -A
# Expose the SSH port
EXPOSE 22

# Start SSH server on container startup
ENTRYPOINT ["/usr/sbin/sshd", "-D"]
