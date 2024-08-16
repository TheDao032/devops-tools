# Use an official Ubuntu base image
FROM ubuntu:20.04

# Set environment variables to avoid interactive prompts
ENV DEBIAN_FRONTEND=noninteractive

# Update and install necessary packages
RUN apt-get update && \
    apt-get install -y \
        openssh-server \
        sudo \
        vim \
        && rm -rf /var/lib/apt/lists/*

# Create SSH directory and set up the SSH server configuration
RUN mkdir /var/run/sshd

# Set root password from environment variable
ARG SSH_PASSWORD
RUN echo "vagrant:${SSH_PASSWORD}" | chpasswd

# Allow root login and password authentication in SSH
RUN sed -i 's/^#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config
RUN sed -i 's/^#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config

# Expose port 22 for SSH access
EXPOSE 22

# Start the SSH service and keep the container running
CMD ["/usr/sbin/sshd", "-D"]
