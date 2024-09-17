#!/usr/bin/env bash

set -e
NGINX_CONFIG_PATH=$1

declare -A nginx_conf=(
  ["include"]="include /etc/nginx/load-balancer/*.conf;"
)

for key in "${!nginx_conf[@]}"; do
  key="${key}"
  value="${nginx_conf[${key}]}"
  if ! grep -Fxq "${value}" ${NGINX_CONFIG_PATH}; then
    sed -i "/^${key}/a\\${value}" ${NGINX_CONFIG_PATH}
  else
    exit 0
  fi
done

# Disable SELinux Temporary
# setcap 'cap_net_bind_service=+ep' /usr/sbin/nginx
# setenforce 0

# Modify SELinux Configuration for NGINX
semanage port -a -t http_port_t -p tcp 6445

exit 0
