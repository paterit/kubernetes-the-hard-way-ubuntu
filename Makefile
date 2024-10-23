.PHONY: all all-machines-launch jumpbox-launch machines-launch machines-delete create-snapshots restore-snapshots
.PHONY: jumpbox-prep jumpbox-install-packages jumpbox-git-clone-k8s-the-hard-way jumpbox-download jumpbox-install-kubectl
.PHONY: configure-ssh-access machine-database enable-root-ssh-access generate-ssh-keys copy-ssh-keys verify-ssh-access set-hostnames verify-hostnames add-hosts-entries verify-hosts-entries
.PHONY: provisioning-ca-generate-tls-certificates generate-ca-files create-client-server-certificates copy-keys-certs-to-nodes copy-certs-pkeys-to-server ca-files-clean

MACHINES := jumpbox server node-0 node-1
SNAP := "snap"

# Color variables
MSG_COLOR := \033[0;32m # green
NC := \033[0m # No Color

all: all-machines-launch jumpbox-prep configure-ssh-access provisioning-ca-generate-tls-certificates

reset-all: machines-delete all

# Prerequisites

all-machines-launch: machines-launch jumpbox-launch

jumpbox-launch:
	@printf "$(MSG_COLOR)Running target: %s$(NC)\n" "$@"
	@multipass launch -n jumpbox -c 1 -m 512MB -d 10GB
	
machines-launch:
	@printf "$(MSG_COLOR)Running target: %s$(NC)\n" "$@"
	multipass launch -n server -c 1 -m 2G -d 20GB
	multipass launch -n node-0 -c 1 -m 2G -d 20GB
	multipass launch -n node-1 -c 1 -m 2G -d 20GB

## Supportive Commands

machines-delete:
	@printf "$(MSG_COLOR)Running target: %s$(NC)\n" "$@"
	-for machine in $(MACHINES); do \
		multipass stop $$machine; \
		multipass delete $$machine; \
	done
	multipass purge

create-snapshots:
	@printf "$(MSG_COLOR)Running target: %s$(NC)\n" "$@"
	for machine in $(MACHINES); do \
		multipass stop $$machine; \
		multipass delete --purge $$machine.$(SNAP); \
		multipass snapshot -n $(SNAP) $$machine; \
		multipass start $$machine; \
	done

restore-snapshots:
	@printf "$(MSG_COLOR)Running target: %s$(NC)\n" "$@"
	for machine in $(MACHINES); do \
		multipass stop $$machine; \
		multipass restore --destructive $$machine.$(SNAP); \
		multipass start $$machine; \
	done

# Set Up The Jumpbox

jumpbox-prep: jumpbox-install-packages jumpbox-git-clone-k8s-the-hard-way jumpbox-download jumpbox-install-kubectl

jumpbox-install-packages:
	@printf "$(MSG_COLOR)Running target: %s$(NC)\n" "$@"
	multipass exec jumpbox -- sudo apt update
	multipass exec jumpbox -- sudo apt install -y wget curl vim openssl git
	
jumpbox-git-clone-k8s-the-hard-way:
	@printf "$(MSG_COLOR)Running target: %s$(NC)\n" "$@"
	multipass exec jumpbox -- git clone --depth 1 https://github.com/paterit/kubernetes-the-hard-way-ubuntu.git kubernetes-the-hard-way

jumpbox-download:
	@printf "$(MSG_COLOR)Running target: %s$(NC)\n" "$@"
	multipass exec jumpbox --working-directory /home/ubuntu/kubernetes-the-hard-way -- mkdir downloads
	multipass exec jumpbox --working-directory /home/ubuntu/kubernetes-the-hard-way -- wget -q --show-progress --https-only --timestamping -P downloads -i downloads.txt
	
jumpbox-install-kubectl:
	@printf "$(MSG_COLOR)Running target: %s$(NC)\n" "$@"
	multipass exec jumpbox --working-directory /home/ubuntu/kubernetes-the-hard-way -- chmod +x downloads/kubectl
	multipass exec jumpbox --working-directory /home/ubuntu/kubernetes-the-hard-way -- sudo cp downloads/kubectl /usr/local/bin
	multipass exec jumpbox --working-directory /home/ubuntu/kubernetes-the-hard-way -- kubectl version --client

# Provisioning Compute Resources

configure-ssh-access: machine-database enable-root-ssh-access generate-ssh-keys copy-ssh-keys verify-ssh-access set-hostnames verify-hostnames add-hosts-entries verify-hosts-entries

machine-database:
	@printf "$(MSG_COLOR)Running target: %s$(NC)\n" "$@"
	echo "IPV4_ADDRESS FQDN HOSTNAME POD_SUBNET" > machines.txt
	echo "$$(multipass info server | grep IPv4 | awk '{print $$2}') server.kubernetes.local server" >> machines.txt
	echo "$$(multipass info node-0 | grep IPv4 | awk '{print $$2}') node-0.kubernetes.local node-0 10.200.0.0/24" >> machines.txt
	echo "$$(multipass info node-1 | grep IPv4 | awk '{print $$2}') node-1.kubernetes.local node-1 10.200.1.0/24" >> machines.txt
	cat machines.txt | multipass exec jumpbox -- bash -c "cat > /home/ubuntu/machines.txt"

enable-root-ssh-access:
	@printf "$(MSG_COLOR)Running target: %s$(NC)\n" "$@"
	for machine in $(MACHINES); do \
		multipass exec $$machine -- sudo sed -i 's/^#PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config; \
		multipass exec $$machine -- sudo systemctl restart ssh.service; \
	done

generate-ssh-keys:
	@printf "$(MSG_COLOR)Running target: %s$(NC)\n" "$@"
	multipass exec jumpbox -- ssh-keygen -t rsa -b 2048 -f /home/ubuntu/.ssh/id_rsa -N "" -q

copy-ssh-keys:
	@printf "$(MSG_COLOR)Running target: %s$(NC)\n" "$@"
	for machine in $(MACHINES); do \
		multipass exec jumpbox -- cat /home/ubuntu/.ssh/id_rsa.pub | multipass exec $$machine -- bash -c "cat >> ~/.ssh/authorized_keys"; \
	done

## multipass makes host visible by their names, so we can use it in ssh command and we can skip setting /etc/hosts on all machines
verify-ssh-access:
	@printf "$(MSG_COLOR)Running target: %s$(NC)\n" "$@"
	for machine in $(MACHINES); do \
		multipass exec jumpbox -- ssh -o StrictHostKeyChecking=no -n ubuntu@$$machine uname -o -m; \
	done

set-hostnames:
	@printf "$(MSG_COLOR)Running target: %s$(NC)\n" "$@"
	multipass exec server -- sudo hostnamectl set-hostname server.kubernetes.local
	multipass exec node-0 -- sudo hostnamectl set-hostname node-0.kubernetes.local
	multipass exec node-1 -- sudo hostnamectl set-hostname node-1.kubernetes.local

verify-hostnames:
	@printf "$(MSG_COLOR)Running target: %s$(NC)\n" "$@"
	for machine in $(MACHINES); do \
		multipass exec jumpbox -- ssh -n ubuntu@$$machine hostname --fqdn ; \
	done

add-hosts-entries:
	@printf "$(MSG_COLOR)Running target: %s$(NC)\n" "$@"
	echo "# Kubernetes the hard way" > hosts
	for machine in $(MACHINES); do \
		echo "$$(multipass info $$machine | grep IPv4 | awk '{print $$2}') $$machine.kubernetes.local $$machine" >> hosts; \
		CMD="sudo sed -i 's/^127.0.1.1.*/127.0.1.1 $$machine.kubernetes.local $$machine/' /etc/hosts"; \
		multipass exec jumpbox -- ssh -n ubuntu@$$machine "$$CMD"; \
	done
	multipass transfer hosts jumpbox:/home/ubuntu/hosts

	for machine in $(MACHINES); do \
		multipass exec jumpbox -- scp -q /home/ubuntu/hosts ubuntu@$$machine:/home/ubuntu/hosts; \
		multipass exec jumpbox -- ssh -n ubuntu@$$machine "cat /home/ubuntu/hosts | sudo tee -a /etc/hosts > /dev/null "; \
		multipass exec jumpbox -- ssh -n ubuntu@$$machine "cat /home/ubuntu/hosts | sudo tee -a /etc/cloud/templates/hosts.debian.tmpl > /dev/null" ; \
	done

verify-hosts-entries:
	@printf "$(MSG_COLOR)Running target: %s$(NC)\n" "$@"
	multipass exec jumpbox -- ping -c 1 server.kubernetes.local
	multipass exec server -- ping -c 1 node-0.kubernetes.local
	multipass exec node-0 -- ping -c 1 node-1.kubernetes.local
	multipass exec node-1 -- ping -c 1 jumpbox.kubernetes.local

# Provisioning a CA and Generating TLS Certificates

provisioning-ca-generate-tls-certificates: generate-ca-files create-client-server-certificates copy-keys-certs-to-nodes copy-certs-pkeys-to-server

generate-ca-files:
	@printf "$(MSG_COLOR)Running target: %s$(NC)\n" "$@"
	-rm -rf ca_files
	mkdir -p ca_files
	cp ca.conf ca_files/
	cd ca_files && \
	openssl genrsa -out ca.key 4096 && \
	openssl req -x509 -new -sha512 -noenc \
		-key ca.key -days 3653 \
		-config ca.conf \
		-out ca.crt

CERTS = admin node-0 node-1 kube-proxy kube-scheduler kube-controller-manager kube-api-server service-accounts

create-client-server-certificates:
	@printf "$(MSG_COLOR)Running target: %s$(NC)\n" "$@"
	for cert in $(CERTS); do \
		cd ca_files && \
		openssl genrsa -out $$cert.key 4096 && \
		openssl req -new -sha256 \
			-key $$cert.key \
			-config ca.conf \
			-section $$cert \
			-out $$cert.csr && \
		openssl x509 -req -in $$cert.csr \
			-copy_extensions copyall \
			-CA ca.crt \
			-CAkey ca.key \
			-CAcreateserial \
			-days 3653 \
			-sha256 \
			-out $$cert.crt && \
		cd ..; \
	done

copy-keys-certs-to-nodes:
	@printf "$(MSG_COLOR)Running target: %s$(NC)\n" "$@"
	for machine in node-0 node-1; do \
		multipass exec $$machine -- sudo mkdir -p /var/lib/kubelet; \
	 	multipass transfer ca_files/ca.crt $$machine:/home/ubuntu/ca.crt; \
	 	multipass transfer ca_files/$$machine.crt $$machine:/home/ubuntu/kubelet.crt; \
	 	multipass transfer ca_files/$$machine.key $$machine:/home/ubuntu/kubelet.key; \
		multipass exec $$machine -- sudo mv /home/ubuntu/ca.crt /var/lib/kubelet/ca.crt; \
		multipass exec $$machine -- sudo mv /home/ubuntu/kubelet.crt /var/lib/kubelet/kubelet.crt; \
		multipass exec $$machine -- sudo mv /home/ubuntu/kubelet.key /var/lib/kubelet/kubelet.key; \
	done

SERVER_CERTS = ca kube-api-server service-accounts

copy-certs-pkeys-to-server:
	@printf "$(MSG_COLOR)Running target: %s$(NC)\n" "$@"
	for cert in $(SERVER_CERTS); do \
		multipass transfer ca_files/$$cert.crt server:/home/ubuntu/$$cert.crt; \
		multipass transfer ca_files/$$cert.key server:/home/ubuntu/$$cert.key; \
	done

# Generating Kubernetes Configuration Files for Authentication

make generate-kubeconfig-files: generate-kubeconfig-nodes generate-kubeconfig-server generate-kubeconfig-admin copy-kube-configfiles-to-nodes copy-kube-configfiles-to-server

generate-kubeconfig-nodes:
	@printf "$(MSG_COLOR)Running target: %s$(NC)\n" "$@"
	for host in node-0 node-1; do \
		cd ca_files && \
		kubectl config set-cluster kubernetes-the-hard-way \
			--certificate-authority=ca.crt \
			--embed-certs=true \
			--server=https://server.kubernetes.local:6443 \
			--kubeconfig=$$host.kubeconfig && \
		kubectl config set-credentials system:node:$$host \
			--client-certificate=$$host.crt \
			--client-key=$$host.key \
			--embed-certs=true \
			--kubeconfig=$$host.kubeconfig && \
		kubectl config set-context default \
			--cluster=kubernetes-the-hard-way \
			--user=system:node:$$host \
			--kubeconfig=$$host.kubeconfig && \
		kubectl config use-context default \
			--kubeconfig=$$host.kubeconfig && \
		cd ..; \
	done

generate-kubeconfig-server:
	@printf "$(MSG_COLOR)Running target: %s$(NC)\n" "$@"
	for host in kube-controller-manager kube-scheduler kube-proxy; do \
		cd ca_files && \
		kubectl config set-cluster kubernetes-the-hard-way \
			--certificate-authority=ca.crt \
			--embed-certs=true \
			--server=https://server.kubernetes.local:6443 \
			--kubeconfig=$$host.kubeconfig && \
		kubectl config set-credentials system:$$host \
			--client-certificate=$$host.crt \
			--client-key=$$host.key \
			--embed-certs=true \
			--kubeconfig=$$host.kubeconfig && \
		kubectl config set-context default \
			--cluster=kubernetes-the-hard-way \
			--user=system:$$host \
			--kubeconfig=$$host.kubeconfig && \
		kubectl config use-context default \
			--kubeconfig=$$host.kubeconfig && \
		cd ..; \
	done

generate-kubeconfig-admin:
	@printf "$(MSG_COLOR)Running target: %s$(NC)\n" "$@"
	for host in admin; do \
		cd ca_files && \
		kubectl config set-cluster kubernetes-the-hard-way \
			--certificate-authority=ca.crt \
			--embed-certs=true \
			--server=https://127.0.0.1:6443 \
			--kubeconfig=$$host.kubeconfig && \
		kubectl config set-credentials $$host \
			--client-certificate=$$host.crt \
			--client-key=$$host.key \
			--embed-certs=true \
			--kubeconfig=$$host.kubeconfig && \
		kubectl config set-context default \
			--cluster=kubernetes-the-hard-way \
			--user=$$host \
			--kubeconfig=$$host.kubeconfig && \
		kubectl config use-context default \
			--kubeconfig=$$host.kubeconfig && \
		cd ..; \
	done

copy-kube-configfiles-to-nodes:
	@printf "$(MSG_COLOR)Running target: %s$(NC)\n" "$@"
	for machine in node-0 node-1; do \
		multipass exec $$machine -- sudo mkdir -p /var/lib/kube-proxy; \
	 	multipass transfer ca_files/kube-proxy.kubeconfig $$machine:/home/ubuntu/kube-proxy.kubeconfig; \
	 	multipass transfer ca_files/$$machine.kubeconfig $$machine:/home/ubuntu/$$machine.kubeconfig; \
		multipass exec $$machine -- sudo mv /home/ubuntu/kube-proxy.kubeconfig /var/lib/kube-proxy/kubeconfig; \
		multipass exec $$machine -- sudo mv /home/ubuntu/$$machine.kubeconfig /var/lib/kubelet/kubeconfig; \
	done


copy-kube-configfiles-to-server:
	@printf "$(MSG_COLOR)Running target: %s$(NC)\n" "$@"
	multipass transfer ca_files/kube-controller-manager.kubeconfig server:/home/ubuntu/kube-controller-manager.kubeconfig
	multipass transfer ca_files/admin.kubeconfig server:/home/ubuntu/admin.kubeconfig
	multipass transfer ca_files/kube-scheduler.kubeconfig server:/home/ubuntu/kube-scheduler.kubeconfig


ca-files-clean:
	@printf "$(MSG_COLOR)Running target: %s$(NC)\n" "$@"
	-rm -rf ca_files

# Generating the Data Encryption Config and Key

generate-encryption-key:
	@printf "$(MSG_COLOR)Running target: %s$(NC)\n" "$@"
	export ENCRYPTION_KEY=$$(head -c 32 /dev/urandom | base64) && \
	envsubst < configs/encryption-config.yaml > ca_files/encryption-config.yaml