#!/bin/bash

set -e
ENVIRONMENT=${ENVIRONMENT:-"local"}
PROVIDER=${PROVIDER:-"docker"}
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

REPOSITORY=${REPOSITORY:-"nthedao"}
IMAGE=${IMAGE:-"ubuntu"}
TAG=${IMAGE:-"latest"}
VAGRANT_PASS=vagrant

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
      # log_info "Installing Vagrant plugin: ${plugin}"
      #
      # vagrant plugin install "${plugin}"
      # if [ $? -eq 0 ]; then
      #     log_info "${plugin} installed successfully."
      # else
      #     log_error "Failed to install ${plugin}."
      # fi
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

  cd ${VAGRANT_DIR} && VAGRANT_VAGRANTFILE=docker.Vagrantfile REPOSITORY=${REPOSITORY} IMAGE=${IMAGE} TAG=${TAG} vagrant up
}

# Docker setup
docker_init() {
  local network=$1
  local driver=$2
  local subnet=$3
  if docker network ls --format '{{.Name}}' | grep -q "^${network}$"; then
    log_info "Docker network '${network}' already exists."
  else
    log_info "Docker network '${network}' does not exist."
    docker network create --driver=${driver} --subnet=${subnet} ${network}
  fi

  docker build -t ${REPOSITORY}/${IMAGE}:${TAG} --build-arg="VAGRANT_PASS=${VAGRANT_PASS}" -f dockerfiles/vagrant.Dockerfile .
}

ansible_exec() {
  local group=$1
  log_info "Running setup PostgreSQL as ${group}."
  if [ "${group}" = "master" ]; then
    # PostgreSQL Common Packages
    log_info "Running setup PostgreSQL common packages as ${group}."
    ansible-playbook ${ANSIBLE_PLAYBOOKS_DIR}/postgresql-playbooks/common/dependencies.yml -i ${ANSIBLE_INVENTORIES_DIR}/${ENVIRONMENT}/${PROVIDER}/master -vvv
    if [ $? -eq 0 ]; then
        log_info "log" "Ansible PostgreSQL common packages for ${group} exec successfully."
    else
        log_info "error" "Ansible PostgreSQL common packages for ${group} failed to exec."

        exit 1
    fi

    # PostgreSQL Citus Setup
    log_info "Running setup PostgreSQL Citus as ${group}."
    ansible-playbook ${ANSIBLE_PLAYBOOKS_DIR}/postgresql-playbooks/citus/common.yml -i ${ANSIBLE_INVENTORIES_DIR}/${ENVIRONMENT}/${PROVIDER}/master -vvv
    ansible-playbook ${ANSIBLE_PLAYBOOKS_DIR}/postgresql-playbooks/citus/coordinator-conn-worker.yml -i ${ANSIBLE_INVENTORIES_DIR}/${ENVIRONMENT}/${PROVIDER}/master -vvv
    log_success "Running setup PostgreSQL Citus as ${group} successfully."

    # PostgreSQL Repmgr Setup
    # Master
    log_info "Running setup PostgreSQL Repmgr as ${group}."
    ansible-playbook ${ANSIBLE_PLAYBOOKS_DIR}/postgresql-playbooks/repmgr/common.yml -i ${ANSIBLE_INVENTORIES_DIR}/${ENVIRONMENT}/${PROVIDER}/master -vvv
    ansible-playbook ${ANSIBLE_PLAYBOOKS_DIR}/postgresql-playbooks/repmgr/primary-conf.yml -i ${ANSIBLE_INVENTORIES_DIR}/${ENVIRONMENT}/${PROVIDER}/master -vvv
    ansible-playbook ${ANSIBLE_PLAYBOOKS_DIR}/postgresql-playbooks/repmgr/primary-register.yml -i ${ANSIBLE_INVENTORIES_DIR}/${ENVIRONMENT}/${PROVIDER}/master -vvv
    log_info "Running setup PostgreSQL Repmgr as ${group} successfully."

    # PostgreSQL Pgbouncer Setup
    log_info "Running setup PostgreSQL Pgbouncer as ${group}."
    ansible-playbook ${ANSIBLE_PLAYBOOKS_DIR}/postgresql-playbooks/pgbouncer/common.yml -i ${ANSIBLE_INVENTORIES_DIR}/${ENVIRONMENT}/${PROVIDER}/master -vvv
    log_info "Running setup PostgreSQL Pgbouncer as ${group} successfully."
  else
    # PostgreSQL Common Packages
    log_info "Running setup PostgreSQL common packages as ${group}."
    ansible-playbook ${ANSIBLE_PLAYBOOKS_DIR}/postgresql-playbooks/common/dependencies.yml -i ${ANSIBLE_INVENTORIES_DIR}/${ENVIRONMENT}/${PROVIDER}/replica -vvv
    log_success "Running setup PostgreSQL common packages as ${group} successfully."

    # PostgreSQL Repmgr Setup
    # Slave
    log_info "Running setup PostgreSQL Repmgr as ${group}."
    ansible-playbook ${ANSIBLE_PLAYBOOKS_DIR}/postgresql-playbooks/repmgr/common.yml -i ${ANSIBLE_INVENTORIES_DIR}/${ENVIRONMENT}/${PROVIDER}/replica -vvv
    ansible-playbook ${ANSIBLE_PLAYBOOKS_DIR}/postgresql-playbooks/repmgr/standby-conf.yml -i ${ANSIBLE_INVENTORIES_DIR}/${ENVIRONMENT}/${PROVIDER}/replica -vvv
    ansible-playbook ${ANSIBLE_PLAYBOOKS_DIR}/postgresql-playbooks/repmgr/standby-register.yml -i ${ANSIBLE_INVENTORIES_DIR}/${ENVIRONMENT}/${PROVIDER}/replica -vvv
    log_info "Running setup PostgreSQL Repmgr as ${group} successfully."
  fi
}

docker_init ${DOCKER_NETWORK_NAME} ${DOCKER_NETWORK_DRIVER} ${DOCKER_NETWORK_SUBNET}
vagrant_init ${vagrant_plugins[@]}

ansible_exec ${VM_ENV_INVENTORY}
