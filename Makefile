.PHONY: all all-machines-launch jumpbox-launch machines-launch machines-delete create-snapshots restore-snapshots
.PHONY: jumpbox-prep jumpbox-install-packages jumpbox-git-clone-k8s-the-hard-way jumpbox-download jumpbox-install-kubectl
.PHONY: configure-ssh-access machine-database enable-root-ssh-access generate-ssh-keys copy-ssh-keys verify-ssh-access

MACHINES := jumpbox server node-0 node-1
SNAP := "snap"

all: all-machines-launch jumpbox-prep configure-ssh-access

# Prerequisites

all-machines-launch: machines-launch jumpbox-launch

jumpbox-launch:
	@multipass launch -n jumpbox -c 1 -m 512MB -d 10GB
	
machines-launch: 
	multipass launch -n server -c 1 -m 2G -d 20GB
	multipass launch -n node-0 -c 1 -m 2G -d 20GB
	multipass launch -n node-1 -c 1 -m 2G -d 20GB

## Supportive Commands

machines-delete:
	for machine in $(MACHINES); do \
		multipass stop $$machine; \
		multipass delete $$machine; \
	done
	multipass purge

create-snapshots:
	for machine in $(MACHINES); do \
		multipass stop $$machine; \
		multipass delete --purge $$machine.$(SNAP); \
		multipass snapshot -n $(SNAP) $$machine; \
		multipass start $$machine; \
	done

restore-snapshots:
	for machine in $(MACHINES); do \
		multipass stop $$machine; \
		multipass restore --destructive $$machine.$(SNAP); \
		multipass start $$machine; \
	done

# Set Up The Jumpbox

jumpbox-prep: jumpbox-install-packages jumpbox-git-clone-k8s-the-hard-way jumpbox-download jumpbox-install-kubectl

jumpbox-install-packages:
	multipass exec jumpbox -- sudo apt update
	multipass exec jumpbox -- sudo apt install -y wget curl vim openssl git
	
jumpbox-git-clone-k8s-the-hard-way:
	multipass exec jumpbox -- git clone --depth 1 https://github.com/paterit/kubernetes-the-hard-way-ubuntu.git kubernetes-the-hard-way

jumpbox-download:
	multipass exec jumpbox --working-directory /home/ubuntu/kubernetes-the-hard-way -- mkdir downloads
	multipass exec jumpbox --working-directory /home/ubuntu/kubernetes-the-hard-way -- wget -q --show-progress --https-only --timestamping -P downloads -i downloads.txt
	
jumpbox-install-kubectl:
	multipass exec jumpbox --working-directory /home/ubuntu/kubernetes-the-hard-way -- chmod +x downloads/kubectl
	multipass exec jumpbox --working-directory /home/ubuntu/kubernetes-the-hard-way -- sudo cp downloads/kubectl /usr/local/bin
	multipass exec jumpbox --working-directory /home/ubuntu/kubernetes-the-hard-way -- kubectl version --client

# Provisioning Compute Resources

configure-ssh-access: machine-database enable-root-ssh-access generate-ssh-keys copy-ssh-keys verify-ssh-access

machine-database:
	echo "IPV4_ADDRESS FQDN HOSTNAME POD_SUBNET" > machines.txt
	echo "$$(multipass info server | grep IPv4 | awk '{print $$2}') server.kubernetes.local server" >> machines.txt
	echo "$$(multipass info node-0 | grep IPv4 | awk '{print $$2}') node-0.kubernetes.local node-0 10.200.0.0/24" >> machines.txt
	echo "$$(multipass info node-1 | grep IPv4 | awk '{print $$2}') node-1.kubernetes.local node-1 10.200.1.0/24" >> machines.txt
	cat machines.txt | multipass exec jumpbox -- bash -c "cat > /home/ubuntu/machines.txt"

enable-root-ssh-access:
	for machine in $(MACHINES); do \
		multipass exec $$machine -- sudo sed -i 's/^#PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config; \
		multipass exec $$machine -- sudo systemctl restart ssh.service; \
	done

generate-ssh-keys:
	multipass exec jumpbox -- ssh-keygen -t rsa -b 2048 -f /home/ubuntu/.ssh/id_rsa -N "" -q

copy-ssh-keys:
	for machine in $(MACHINES); do \
		multipass exec jumpbox -- cat /home/ubuntu/.ssh/id_rsa.pub | multipass exec $$machine -- bash -c "cat >> ~/.ssh/authorized_keys"; \
	done

## multipass makes host visible by their names, so we can use it in ssh command and we can skip setting /etc/hosts on all machines
verify-ssh-access:
	for machine in $(MACHINES); do \
		multipass exec jumpbox -- ssh -o StrictHostKeyChecking=no -n ubuntu@$$machine uname -o -m; \
	done

