#!/usr/bin/env bash
#
# Set up /etc/hosts so we can resolve all the nodes
set -e

IP_NW=$1
BUILD_MODE=$2
shift 2  # Shift arguments to the left by 2 to get the list of machines

# List of machines
MACHINES=("$@")  # Remaining arguments are the machine list
# Convert the space-separated string into an array
IFS=' ' read -r -a MACHINE_ARRAY <<< "$MACHINES"

if [ "$BUILD_MODE" = "BRIDGE" ]; then
    # Determine machine IP from route table -
    # Interface that routes to default GW that isn't on the NAT network.
    MY_IP="$(ip route | grep default | grep -Pv '10\.\d+\.\d+\.\d+' | awk '{ print $9 }')"

    # From this, determine the network (which for average broadband we assume is a /24)
    MY_NETWORK=$(echo $MY_IP | awk 'BEGIN {FS="."} ; { printf("%s.%s.%s", $1, $2, $3) }')

    # Create a script that will return this machine's IP to the bridge post-provisioner.
    cat <<EOF > /usr/local/bin/public-ip
#!/usr/bin/env sh
echo -n "$(ip route | grep default | grep -Pv '10\.\d+\.\d+\.\d+' | awk '{ print $9 }')"
EOF
    chmod +x /usr/local/bin/public-ip
else
    # Determine machine IP from route table -
    # Interface that is connected to the NAT network.
    MY_IP=$(ip route | grep "^$IP_NW" | awk '{print $NF}')
    MY_NETWORK=$IP_NW
fi

# Remove unwanted entries
sed -e '/^.*ubuntu-jammy.*/d' -i /etc/hosts
sed -e "/^.*${HOSTNAME}.*/d" -i /etc/hosts

# Export PRIMARY IP as an environment variable
echo "PRIMARY_IP=${MY_IP}" >> /etc/environment

# Export architecture as environment variable to download correct versions of software
echo "ARCH=amd64" | sudo tee -a /etc/environment > /dev/null

[ "$BUILD_MODE" = "BRIDGE" ] && exit 0

# Update /etc/hosts with the list of machines
for machine in "${MACHINE_ARRAY[@]}"; do
  IFS=':' read -r name ip <<< "$machine"
  echo "${ip} ${name}" >> /etc//hosts
done

exit 0
