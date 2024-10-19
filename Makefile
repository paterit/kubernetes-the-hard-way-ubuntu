.PHONY: machines-launch

prep-machines: jumpbox-prep machines-launch

jumpbox-prep: jumpbox-launch jumpbox-install-packages jumpbox-git-clone-k8s-the-hard-way jumpbox-download jumpbox-install-kubectl

jumpbox-launch:
	@multipass launch -n jumpbox -c 1 -m 512MB -d 10GB
	
machines-launch: 
	multipass launch -n server -c 1 -m 2G -d 20GB
	multipass launch -n node-0 -c 1 -m 2G -d 20GB
	multipass launch -n node-1 -c 1 -m 2G -d 20GB

machines-delete:
	-multipass delete jumpbox 
	-multipass delete server
	-multipass delete node-0
	-multipass delete node-1
	multipass purge

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
	
	
	
