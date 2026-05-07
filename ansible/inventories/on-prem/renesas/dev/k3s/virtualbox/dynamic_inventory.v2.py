# #!/usr/bin/env python3
#
# from ansible.cli import CLI
# from ansible.template import Templar
# from ansible.vars.manager import VariableManager
# from ansible.parsing.dataloader import DataLoader
# from ansible.inventory.manager import InventoryManager
# import ansible.constants as C
# import os
#
# def main():
#     # The DataLoader is responsible for loading yaml/json content
#     loader = DataLoader()
#
#     # Setup vault secrets (optional, if you're using vault)
#     vault_secrets = CLI.setup_vault_secrets(
#         loader,
#         vault_ids=C.DEFAULT_VAULT_IDENTITY_LIST,
#     )
#     loader.set_vault_secrets(vault_secrets)
#
#     # Set the base directory for Ansible (update with your structure)
#     # This is where your playbooks and inventories are located
#     base_dir = 'playbooks'
#     loader.set_basedir(base_dir)
#
#     # Define inventory sources
#     inventory_sources = [
#         'inventories/local/k3s/virtualbox',
#         'inventories/local/psql/virtualbox',
#         'inventories/local/vault/virtualbox',
#     ]
#
#     # The InventoryManager creates and manages the inventory using the provided loader
#     inventory = InventoryManager(loader=loader, sources=inventory_sources)
#
#     # The VariableManager loads variables using the provided loader and inventory
#     variable_manager = VariableManager(loader=loader, inventory=inventory)
#
#     # Iterate through all hosts in the inventory
#     for host in inventory.get_hosts():
#         print(f"Host: {host.name}")
#         # Get host-specific variables
#         host_vars = variable_manager.get_vars(host=host)
#
#         # The templar helps us resolve variable values, including Jinja2 templates
#         templar = Templar(loader=loader, variables=host_vars)
#
#         # Output each variable and its resolved value
#         for var_name, var_value in host_vars.items():
#             try:
#                 # Use the templar to resolve any Jinja2 expressions
#                 resolved_value = templar.template(var_value)
#                 print(f"{var_name}: {resolved_value}")
#             except Exception as e:
#                 # If the variable can't be templated, just show the raw value
#                 print(f"{var_name}: {var_value} (failed to resolve, error: {e})")
#
# if __name__ == '__main__':
#     main()
