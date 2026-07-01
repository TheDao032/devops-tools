# inventory: local/k3s/qemu

Targets the running **vagrant-qemu** k3s lab at
`vagrant/vagrant-files/k3s/` (5 VMs on `192.168.105.0/24`).

## Usage

```bash
cd ansible/inventories/local/k3s/qemu

# 1. Generate ssh.config from the running VMs (per-VM forwarded ports + keys)
./gen-ssh-config.sh

# 2. Sanity-check the inventory
ansible-inventory -i inventory.yml --graph

# 3. Reach every node
ansible -i inventory.yml all -m ping

# 4. Deploy k3s (external etcd + HAProxy)
ansible-playbook -i inventory.yml ../../../../playbooks/k3s-etcd-playbooks/site.yml
```

> Point `-i` at **`inventory.yml`** (the file), not the directory — the dir also
> contains `gen-ssh-config.sh`, which Ansible would try (and fail) to parse as an
> inventory source. `group_vars/` still loads from alongside the file.

## Groups

```
etcd    → k3s-lb            (external etcd datastore :2379)
infra   → k3s-lb            (HAProxy :6443 — same box as etcd)
server  → k3s-server-1/2    (control-plane, external datastore)
agent   → k3s-agent-1/2     (workers)
```

## How connection works

vagrant-qemu forwards each VM's SSH to `127.0.0.1:5001x` with a per-VM key. Instead of
hardcoding those, `gen-ssh-config.sh` runs `vagrant ssh-config` (Host entries match the
inventory names) and `group_vars/all.yml` points Ansible at it via
`ansible_ssh_common_args: -F {{ inventory_dir }}/ssh.config`.

`cluster_ip` (per host) is the `192.168.105.x` address used for etcd/HAProxy/flannel
wiring — separate from the SSH connection. `ssh.config` is git-ignored (machine-specific).

> If you gave the VMs static consumable keys (`insert_key=false`) you could instead set
> `ansible_host: <cluster_ip>` directly (the host reaches them over socket_vmnet). The
> ssh.config route is used because the lab lets Vagrant insert per-VM keys.
