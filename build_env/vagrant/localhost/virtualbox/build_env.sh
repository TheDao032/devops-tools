#!/bin/bash

set -e

UTILS_SCRIPT="${UTILS_SCRIPT:-"build_env/utils/setup_env.sh"}"

DEVOPS_TOOLS_DIR=${DEVOPS_TOOLS_DIR:-${PWD}}
VAGRANT_DIR=${VAGRANT_DIR:-${DEVOPS_TOOLS_DIR}/vagrant}
ANSIBLE_DIR=${ANSIBLE_DIR:-${DEVOPS_TOOLS_DIR}/ansible}

ANSIBLE_PLAYBOOKS_DIR=${ANSIBLE_DIR}/playbooks
ANSIBLE_INVENTORIES_DIR=${ANSIBLE_DIR}/inventories

source ${DEVOPS_TOOLS_DIR}/${UTILS_SCRIPT}

DOCKER_NETWORK_DRIVER=bridge
DOCKER_NETWORK_SUBNET=172.20.10.0/24
DOCKER_NETWORK_NAME=vagrant

RHEL_USERNAME=$1
RHEL_PASSWORD=$2
VAGRANT_PASS=vagrant

declare vagrant_plugins=(
  "vagrant-vbguest"
  "vagrant-disksize"
  "vagrant-hostmanager"
)

# Vagrant setup
vagrant_init() {
  local vagrant_plugins=$1
  for plugin in "${vagrant_plugins[@]}"; do
      log_info "Installing Vagrant plugin: ${plugin}"

      vagrant plugin install "${plugin}"
      if [ $? -eq 0 ]; then
          log_info "${plugin} installed successfully."
      else
          log_error "Failed to install ${plugin}."
      fi
  done

  cd ${VAGRANT_DIR} && VAGRANT_VAGRANTFILE=virtualbox.Vagrantfile RHEL_USERNAME=${RHEL_USERNAME} RHEL_PASSWORD=${RHEL_PASSWORD} vagrant up
}

ansible_exec() {

  local group=$1
  log_info "Running setup PostgreSQL as ${group}."

  if [ ${group} -eq "master" ]; then
    # PostgreSQL Common Packages
    log_info "Running setup PostgreSQL common packages as ${group}."
    ansible-playbook ansible/playbooks/postgresql-playbooks/common/dependencies.yml -i ansible/inventories/localhost/docker/master -vvv
    if [ $? -eq 0 ]; then
        log_info "log" "Ansible PostgreSQL common packages for ${group} exec successfully."
    else
        log_info "error" "Ansible PostgreSQL common packages for ${group} failed to exec."

        exit 1
    fi

    # PostgreSQL Citus Setup
    log_info "Running setup PostgreSQL Citus as ${group}."
    ansible-playbook ${ANSIBLE_PLAYBOOKS_DIR}/postgresql-playbooks/citus/common.yml -i ${ANSIBLE_INVENTORIES_DIR}/localhost/docker/master -vvv
    ansible-playbook ${ANSIBLE_PLAYBOOKS_DIR}/playbooks/postgresql-playbooks/citus/coordinator-conn-worker.yml -i ansible/inventories/localhost/docker/master -vvv
    log_success "Running setup PostgreSQL Citus as ${group} successfully."

    # PostgreSQL Repmgr Setup
    # Master
    log_info "Running setup PostgreSQL Repmgr as ${group}."
    ansible-playbook ${ANSIBLE_PLAYBOOKS_DIR}/postgresql-playbooks/repmgr/common.yml -i ${ANSIBLE_INVENTORIES_DIR}/localhost/docker/master -vvv
    ansible-playbook ${ANSIBLE_PLAYBOOKS_DIR}/postgresql-playbooks/repmgr/primary-conf.yml -i ${ANSIBLE_INVENTORIES_DIR}/localhost/docker/master -vvv
    ansible-playbook ${ANSIBLE_PLAYBOOKS_DIR}/postgresql-playbooks/repmgr/primary-register.yml -i ${ANSIBLE_INVENTORIES_DIR}/localhost/docker/master -vvv
    log_info "Running setup PostgreSQL Repmgr as ${group} successfully."

    # PostgreSQL Pgbouncer Setup
    log_info "Running setup PostgreSQL Pgbouncer as ${group}."
    ansible-playbook ${ANSIBLE_PLAYBOOKS_DIR}/postgresql-playbooks/pgbouncer/common.yml -i ${ANSIBLE_INVENTORIES_DIR}/localhost/docker/master -vvv
    log_info "Running setup PostgreSQL Pgbouncer as ${group} successfully."
  else
    # PostgreSQL Common Packages
    log_info "Running setup PostgreSQL common packages as ${group}."
    ansible-playbook ${ANSIBLE_PLAYBOOKS_DIR}/postgresql-playbooks/common/dependencies.yml -i ${ANSIBLE_INVENTORIES_DIR}/localhost/docker/replica -vvv
    log_success "Running setup PostgreSQL common packages as ${group} successfully."

    # PostgreSQL Repmgr Setup
    # Slave
    log_info "Running setup PostgreSQL Repmgr as ${group}."
    ansible-playbook ${ANSIBLE_PLAYBOOKS_DIR}/postgresql-playbooks/repmgr/common.yml -i ${ANSIBLE_INVENTORIES_DIR}/localhost/docker/replica -vvv
    ansible-playbook ${ANSIBLE_PLAYBOOKS_DIR}/postgresql-playbooks/repmgr/standby-conf.yml -i ${ANSIBLE_INVENTORIES_DIR}/localhost/docker/replica -vvv
    ansible-playbook ${ANSIBLE_PLAYBOOKS_DIR}/postgresql-playbooks/repmgr/standby-register.yml -i ${ANSIBLE_INVENTORIES_DIR}/localhost/docker/replica -vvv
    log_info "Running setup PostgreSQL Repmgr as ${group} successfully."
  fi
}

# vagrant_init ${vagrant_plugins[@]}
# docker_init ${DOCKER_NETWORK_NAME} ${DOCKER_NETWORK_DRIVER} ${DOCKER_NETWORK_SUBNET}

ansible_exec "master"
ansible_exec "replica"
