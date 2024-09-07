#!/usr/bin/env bash
#
# Set up /etc/hosts so we can resolve all the nodes
set -e
DOCKER_NETWORK_SUBNET=$1
NUM_SLAVE_CLUSTERS=$2
MASTER_START_IP=$3
SLAVE_START_IP=$3
POOL_START_IP=$3

# Determine machine IP from route table -
# Interface that routes to default GW that isn't on the NAT network.
MY_IP="$(ip route | grep ${DOCKER_NETWORK_SUBNET} | grep -Pv '10\.\d+\.\d+\.\d+' | awk '{ print $9 }')"

# From this, determine the network (which for average broadband we assume is a /24)
MY_NETWORK=$(echo $MY_IP | awk 'BEGIN {FS="."} ; { printf("%s.%s.%s", $1, $2, $3) }')

# Create a script that will return this machine's IP to the bridge post-provisioner.
cat <<EOF > /usr/local/bin/public-ip
#!/usr/bin/env sh
echo -n "$(ip route | grep ${DOCKER_NETWORK_SUBNET} | grep -Pv '10\.\d+\.\d+\.\d+' | awk '{ print $9 }')"
EOF
chmod +x /usr/local/bin/public-ip

# Remove unwanted entries
sed -e '/^.*ubuntu-jammy.*/d' -i /etc/hosts
sed -e "/^.*${HOSTNAME}.*/d" -i /etc/hosts

# Export PRIMARY IP as an environment variable
echo "PRIMARY_IP=${MY_IP}" >> /etc/environment

# Export architecture as environment variable to download correct versions of software
echo "ARCH=amd64"  | sudo tee -a /etc/environment > /dev/null

# Update /etc/hosts about other hosts (NAT mode)
# for i in $(seq 1 $NUM_MASTER_CLUSTERS)
# do
pool_num=$(( $POOL_IP_START ))
echo "${MY_NETWORK}.${pool_num} coordinator" >> /etc//hosts
master_num=$(( $MASTER_IP_START ))
echo "${MY_NETWORK}.${master_num} connection-pool" >> /etc//hosts
# done
for i in $(seq 1 $NUM_SLAVE_CLUSTERSS)
do
    num=$(( $SLAVE_IP_START + $i ))
    echo "${MY_NETWORK}.${num} worker-${i}" >> /etc//hosts
done

exit 0
