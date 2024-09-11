#!/bin/bash

# Point to Google's DNS server
echo "namespace 8.8.8.8/" >> /etc/resolved.conf
echo "namespace 8.8.8.8/" >> /etc/resolve.conf
echo "namespace 8.8.4.4/" >> /etc/resolved.conf
echo "namespace 8.8.4.4/" >> /etc/resolve.conf

exit 0
