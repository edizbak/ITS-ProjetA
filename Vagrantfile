# -*- mode: ruby -*-
# vi: set ft=ruby :
# To enable zsh, please set ENABLE_ZSH env var to "true" before launching vagrant up 
#   + On windows => $env:ENABLE_ZSH="true"
#   + On Linux  => export ENABLE_ZSH="true"

Vagrant.configure("2") do |config|
  config.vm.define "nginx" do |nginx|
    nginx.vm.box = "debian/contrib-buster64"
    nginx.vm.network "private_network", type: "static", ip: "192.168.99.30"
    nginx.vm.hostname = "nginx"
    nginx.vm.provider "virtualbox" do |v|
      v.name = "nginx"
      v.memory = 2048
      v.cpus = 1
    end
    nginx.vm.provision :shell do |shell|
      shell.path = "create_nginx_lb_rp_ca.sh"
      shell.args = ["master", "192.168.99.30"]
      
    end
  end
  config.vm.define "mediawiki1" do |mediawiki1|
    mediawiki1.vm.box = "debian/bullseye64"
    mediawiki1.vm.network "private_network", type: "static", ip: "192.168.99.31"
    mediawiki1.vm.hostname = "mediawiki1"
    mediawiki1.vm.provider "virtualbox" do |v|
      v.name = "mediawiki1"
      v.memory = 2048
      v.cpus = 2
    end
    mediawiki1.vm.provision :shell do |shell|
      shell.path = "install_mediawiki.sh"
      shell.args = ["node1", "192.168.99.31"]
      
    end
  end
  config.vm.define "mediawiki2" do |mediawiki2|
    mediawiki2.vm.box = "debian/bullseye64"
    mediawiki2.vm.network "private_network", type: "static", ip: "192.168.99.32"
    mediawiki2.vm.hostname = "mediawiki2"
    mediawiki2.vm.provider "virtualbox" do |v|
      v.name = "mediawiki2"
      v.memory = 2048
      v.cpus = 2
	  #Création du disque hd
	  v.customize ['createhd', '--filename', 'new_disk1.vdi', '--size', '8192']
	  #Fixer le disque au SATA Controller
	  v.customize ['storageattach', :id, '--storagectl', 'SATA Controller', '--port', '2', '--device', '0', '--type', 'hdd', '--medium', 'new_disk1.vdi']  
    end
    mediawiki2.vm.provision :shell do |shell|
      shell.path = "install_mediawiki.sh"
      shell.args = ["node2", "192.168.99.32"]
	end
  end
end
