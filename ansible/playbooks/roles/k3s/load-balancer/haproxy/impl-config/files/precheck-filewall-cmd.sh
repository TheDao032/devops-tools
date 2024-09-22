#!/bin/bash

# Check if firewalld is running
if systemctl is-active --quiet firewalld; then
    echo "Firewalld is running. Checking if it's enabled."

    # Check if firewalld is enabled
    if systemctl is-enabled --quiet firewalld; then
        echo "Firewalld is enabled. Adding firewall rules."

        # Add ports to the public zone
        sudo firewall-cmd --zone=public --add-port 80/tcp --permanent
        sudo firewall-cmd --zone=public --add-port 443/tcp --permanent
        sudo firewall-cmd --zone=public --add-port 6445/tcp --permanent

        # Reload the firewall to apply changes
        sudo firewall-cmd --reload
        echo "Firewall rules added and firewall reloaded."

    else
        echo "Firewalld is not enabled."
    fi

else
    echo "Firewalld is not running. Please start and enable firewalld."
fi

