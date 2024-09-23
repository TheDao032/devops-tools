#!/bin/bash

set -e
RHEL_USERNAME=$1
RHEL_PASSWORD=$2

LOCATION=${LOCATION:-"localhost"}
SERVICE=${SERVICE:-"k3s"}
PROVIDER=${PROVIDER:-"virtualbox"}
UTILS_SCRIPT="${UTILS_SCRIPT:-"build_env/utils/setup_env.sh"}"

DEVOPS_TOOLS_DIR=${DEVOPS_TOOLS_DIR:-${PWD}}
VAGRANT_DIR=${VAGRANT_DIR:-${DEVOPS_TOOLS_DIR}/vagrant}
ANSIBLE_DIR=${ANSIBLE_DIR:-${DEVOPS_TOOLS_DIR}/ansible}

ANSIBLE_PLAYBOOKS_DIR=${ANSIBLE_DIR}/playbooks/k3s-playbooks
ANSIBLE_INVENTORIES_DIR=${ANSIBLE_DIR}/inventories
VAGRANTFILE="vagrant-files/kubernetes/k3s.${PROVIDER}.Vagrantfile"
INVENTORY=${ANSIBLE_INVENTORIES_DIR}/${LOCATION}/${SERVICE}/${PROVIDER}

source ${DEVOPS_TOOLS_DIR}/${UTILS_SCRIPT}

VM_ENV_INVENTORY=$1

declare vagrant_plugins=(
  "vagrant-vbguest"
  "vagrant-disksize"
  "vagrant-hostmanager"
)

# Vagrant setup
vagrant_init() {
  local vagrant_plugins=$1
  for plugin in "${vagrant_plugins[@]}"; do
    if vagrant plugin list | grep -q "^${plugin} "; then
      log_info "Vagrant plugin '${plugin}' is already installed."
    else
      log_info "Installing Vagrant plugin: ${plugin}"
      vagrant plugin install "${plugin}"
      if [ $? -eq 0 ]; then
        log_info "Vagrant plugin '${plugin}' installed successfully."
      else
        log_error "Failed to install Vagrant plugin '${plugin}'."
      fi
    fi
  done

  cd ${VAGRANT_DIR} && VAGRANT_VAGRANTFILE=${VAGRANTFILE} RHEL_USERNAME=${RHEL_USERNAME} RHEL_PASSWORD=${RHEL_PASSWORD} vagrant up --provider ${PROVIDER}
}

ansible_exec() {
  # k3s PostgreSQL Common Packages
  log_info "Running setup k3s PostgreSQL common packages"
  ansible-playbook ${ANSIBLE_PLAYBOOKS_DIR}/psql-impl/main.yml -i ${INVENTORY} -vvv

  log_info "Running setup k3s load-balancer"
  ansible-playbook ${ANSIBLE_PLAYBOOKS_DIR}/load-balancer/haproxy/main.yml -i ${INVENTORY} -vvv
  ansible-playbook ${ANSIBLE_PLAYBOOKS_DIR}/load-balancer/keepalived/main.yml -i ${INVENTORY} -vvv

  log_info "Running setup k3s server"
  ansible-playbook ${ANSIBLE_PLAYBOOKS_DIR}/server-register/main.yml -i ${INVENTORY} -vvv

  log_info "Running setup k3s agent"
  ansible-playbook ${ANSIBLE_PLAYBOOKS_DIR}/agent-register/main.yml -i ${INVENTORY} -vvv
}

vagrant_init ${vagrant_plugins[@]}

ansible_exec ${VM_ENV_INVENTORY}
