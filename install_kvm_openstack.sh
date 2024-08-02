#!/bin/bash

# Check if virtualization is enabled
if [ "$(egrep -c '(vmx|svm)' /proc/cpuinfo)" -eq 0 ]; then
  echo "Virtualization is not enabled. Please enable it in the BIOS."
  exit 1
fi

# Check if OS is 64-bit
if [ "$(uname -m)" != "x86_64" ]; then
  echo "This script is intended for 64-bit systems only."
  exit 1
fi

# Check for existing KVM modules
if [ -d /lib/modules/$(uname -r)/kernel/arch/x86/kvm ]; then
  echo "KVM modules found."
else
  echo "KVM modules not found. Proceeding with installation."
fi

# Switch to root user and set proxy (if necessary)
sudo -i <<EOF
export http_proxy=http://172.16.0.3:8080

# Update packages and install KVM
apt-get update
apt-get install -y qemu-kvm libvirt-bin bridge-utils virt-manager qemu-system

# Verify KVM installation
if virsh -c qemu:///system list; then
  echo "KVM installation verified."
else
  echo "KVM installation failed."
  exit 1
fi

# Add 'stack' user for OpenStack
adduser --disabled-password --gecos "" stack
echo "stack ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# Switch to 'stack' user
su - stack <<EOL

# Set proxy for 'stack' user
export http_proxy=http://172.16.0.3:8080
export https_proxy=http://172.16.0.3:8080

# Install git
sudo apt-get install -y git

# Clone devstack repository
git config --global http.proxy \$http_proxy
git config --global https.proxy \$https_proxy
git clone http://git.openstack.org/openstack-dev/devstack

# Create local.conf file for OpenStack configuration
cd devstack
cat <<EOL2 > local.conf
[[local|localrc]]
FLOATING_RANGE=192.168.1.224/27
FIXED_RANGE=10.11.11.0/24
FIXED_NETWORK_SIZE=256
FLAT_INTERFACE=eth0
ADMIN_PASSWORD=root
DATABASE_PASSWORD=root
RABBIT_PASSWORD=root
SERVICE_PASSWORD=root
SERVICE_TOCKEN=root
EOL2

# Set file permissions
sudo chown stack * -R

# Run stack.sh to install OpenStack
./stack.sh

# If any error occurs, run the unstack.sh and then stack.sh again
if [ $? -ne 0 ]; then
  ./unstack.sh
  sudo apt-get update
  ./stack.sh
fi

# Display the IP address for accessing OpenStack
echo "OpenStack installed. Access it via http://$(hostname -I | awk '{print $1}')/"

# Create rejoin.sh script for restarting OpenStack services after a reboot
cat <<EOL3 > rejoin.sh
#!/bin/bash
su - stack <<EOL4
cd devstack
./rejoin-stack.sh
EOL4
EOL3

# Make rejoin.sh executable
chmod +x rejoin.sh

EOL

EOF

# End of script


# chmod +x install_kvm_openstack.sh
# ./install_kvm_openstack.sh
