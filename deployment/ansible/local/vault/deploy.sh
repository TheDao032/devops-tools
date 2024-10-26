#!/bin/bash

set -e

ANSIBLE_ENV=${ANSIBLE_ENV:-"local"}
SERVICE=${SERVICE:-"vault"}
PROVIDER=${PROVIDER:-"virtualbox"}
UTILS_SCRIPT="${UTILS_SCRIPT:-"deployment/utils/setup_env.sh"}"

DEVOPS_TOOLS_DIR=${DEVOPS_TOOLS_DIR:-${PWD}}
VAGRANT_DIR=${VAGRANT_DIR:-${DEVOPS_TOOLS_DIR}/vagrant}
ANSIBLE_DIR=${ANSIBLE_DIR:-${DEVOPS_TOOLS_DIR}/ansible}

ANSIBLE_PLAYBOOKS_DIR=${ANSIBLE_DIR}/playbooks/vault-playbooks
ANSIBLE_INVENTORIES_DIR=${ANSIBLE_DIR}/inventories
VAGRANTFILE="vagrant-files/kubernetes/k3s.${PROVIDER}.Vagrantfile"
INVENTORY=${ANSIBLE_INVENTORIES_DIR}/${ANSIBLE_ENV}/${SERVICE}/${PROVIDER}

NETWORK_MODE=${NETWORK_MODE:-"NAT"} VBOX_GUEST_DISK=${VBOX_GUEST_DISK:-"/Applications/VirtualBox.app/Contents/MacOS/VBoxGuestAdditions.iso"}

source ${DEVOPS_TOOLS_DIR}/${UTILS_SCRIPT} || { log_info "$(date -u) - FATAL - failure occured while reading ${LIB_FILE}"; exit 1; }

LIB_FILE=${DEVOPS_TOOLS_DIR}/deployment/ansible/${ANSIBLE_ENV}/env-variables/vault-env.bash
source "${LIB_FILE}" || { log_info "$(date -u) - FATAL - failure occured while reading ${LIB_FILE}"; exit 1; }

RHEL_USERNAME=$1
RHEL_PASSWORD=$2

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

  cd ${VAGRANT_DIR} && VAGRANT_VAGRANTFILE=${VAGRANTFILE} RHEL_USERNAME=${RHEL_USERNAME} RHEL_PASSWORD=${RHEL_PASSWORD} PROVIDER=${PROVIDER} VBOX_GUEST_DISK=${VBOX_GUEST_DISK} NETWORK_MODE=${NETWORK_MODE} vagrant up --provider ${PROVIDER} --provision
}

ansible_exec() {
  log_info "Running setup vault dependencies packages"
  ansible-playbook ${ANSIBLE_PLAYBOOKS_DIR}/dependencies/main.yml -i ${INVENTORY} -vvv
  # ansible-playbook ${ANSIBLE_PLAYBOOKS_DIR}/store-secrets/main.yml -i ${INVENTORY} -vvv
}

# vagrant_init ${vagrant_plugins[@]}

ansible_exec
