#!/bin/bash

# Point to Google's DNS server
echo "namespace 8.8.8.8" >> /etc/resolv.conf
echo "namespace 8.8.4.4" >> /etc/resolv.conf

exit 0
