#!/usr/bin/env python3
import os
import sys
import json
import subprocess
import argparse
import hvac  # Import hvac for Vault access
from dotenv import load_dotenv

# Load environment variables from .env file
load_dotenv()

VAULT_ADDR = os.getenv('VAULT_ADDR', 'http://127.0.0.1:8200')  # Vault address from env or default to local
VAULT_TOKEN = os.getenv('VAULT_TOKEN')  # Vault token from env
ENV = os.getenv('environment', 'local')
client = hvac.Client(url=VAULT_ADDR, token=VAULT_TOKEN)

vms = [
    "server-1",
    "server-2",
    "agent-1",
    "agent-2"
]
# Define a function to get IPs from Vault
def get_ips_from_vault():
    ips = {}

    try:
        # Make sure the client is authenticated with Vault
        if not client.is_authenticated():
            print("Vault authentication failed.", file=sys.stderr)
            return ips

        # Assuming IPs are stored in the secret path 'kv/data/vms' in Vault
        secret_path = f'kv_{ENV}/k3s/vms'
        secret_response = client.secrets.kv.v2.read_secret_version(path=secret_path)
        data = secret_response['data']['data']

        for vm in vms:
            if vm in data:
                ips[vm] = data[vm]

    except Exception as e:
        print(f"Error fetching IPs from Vault: {str(e)}", file=sys.stderr)

    return ips

# Define a function to get IPs from the .env file
def get_ips_from_env():
    ips = {}
    # Example: Fetch IPs for VM, server

    for item in vms:
        ip = os.getenv(item)

        if ip:
            ips[item] = ip

    return ips

# Function to get IP from VirtualBox using 'VBoxManage'
def get_ip_from_virtualbox(vm_name):
    try:
        # Use VBoxManage command to get the VM's IP
        result = subprocess.run(
            ["VBoxManage", "guestproperty", "get", vm_name, "/VirtualBox/GuestInfo/Net/1/V4/IP"],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
        )
        if "Value:" in result.stdout:
            ip_address = result.stdout.strip().split("Value:")[1].strip()
            if ip_address and ip_address != "0.0.0.0":
                return ip_address
        return None
    except Exception as e:
        print(f"Error getting IP for {vm_name}: {str(e)}")
        return None

# Function to generate the inventory
def generate_inventory():
    groups = {
        'all': {
            'children': [
                'server',
                'agent'
            ],
            'vars': {
                'keepalived_virtual_ip': '192.168.56.100',
                'load_balancer_port': 6445,
                'psql_version': 15,
                'k3s_server_cidr_range': '192.168.56.0/24',
                'k3s_version': 'v1.30.2+k3s1',
                'api_endpoint': "{{ hostvars['server-1']['ansible_host'] }}",
                'extra_server_args': '',
                'extra_agent_args': '',
            }
        },

        'server': {
            'hosts': []
        },

        'agent': {
            'hosts': []
        },
    }
    hostvars = {
        '_meta': {
            'hostvars': {}
        }
    }

    # Step 1: Get IPs from Vault first
    ips = get_ips_from_vault()

    # Step 2: If no IPs found in Vault, fallback to .env
    if not ips or not any(ips.values()):
        ips = get_ips_from_env()

    # Step 2: If no IPs found in .env, fallback to VirtualBox
    if not ips or not any(ips.values()):
        # Example VM names in VirtualBox, adjust these as per your VMs
        for vm in vms:
            ip = get_ip_from_virtualbox(vm)
            if ip:
                ips[vm] = ip

    # Step 3: Add discovered IPs to the inventory
    for vm, ip in ips.items():
        if ip:
            if "server" in vm:
                groups['server']['hosts'].append(vm)
            elif "agent" in vm:
                groups['agent']['hosts'].append(vm)

            hostvars['_meta']['hostvars'].update({
                vm: {
                    "ansible_host": ip
                }
            })

    # Step 4: If no IPs were found, handle it gracefully
    if not hostvars["_meta"]["hostvars"]:
        print("No IPs found in .env or VirtualBox", file=sys.stderr)
        return {}

    # Output the inventory in JSON format for Ansible
    inventory = {}
    inventory.update(hostvars)
    inventory.update(groups)

    return inventory

# Parse command-line arguments
def parse_args():
    parser = argparse.ArgumentParser(description="Ansible Dynamic Inventory Script")
    parser.add_argument('--list', action='store_true', help='List all hosts and groups')
    parser.add_argument('--host', help='Get variables about a specific host')
    return parser.parse_args()

if __name__ == "__main__":
    args = parse_args()
    # Generate the dynamic inventory
    inventory = generate_inventory()

    if args.list:
        print(json.dumps(inventory, indent=4))
    elif args.host:
        print(json.dumps(inventory['_meta']['hostvars'].get(args.host, {}), indent=4))
    else:
        print(json.dumps({}))

    # Output as JSON for Ansible
    # print(json.dumps(inventory, indent=4))
    # print(yaml.dump(inventory, default_flow_style=False))
