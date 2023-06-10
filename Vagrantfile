# -*- mode: ruby -*-
# vi: set ft=ruby :
# To enable zsh, please set ENABLE_ZSH env var to "true" before launching vagrant up 
#   + On windows => $env:ENABLE_ZSH="true"
#   + On Linux  => export ENABLE_ZSH="true"

Vagrant.configure("2") do |config|
  config.vm.define "nginx" do |nginx|
    nginx.vm.box = "debian/contrib-buster64"
	# nginx.vm.box_download_insecure=true
    nginx.vm.network "private_network", type: "static", ip: "192.168.99.30"
    nginx.vm.hostname = "nginx"
    nginx.vm.provider "virtualbox" do |v|
      v.name = "nginx"
      v.memory = 2048
      v.cpus = 2
    end
    nginx.vm.provision :shell do |shell|
      shell.path = "create_nginx_lb_rp_ca.sh"
      shell.args = ["master", "192.168.99.10"]
      shell.env = { 'ENABLE_ZSH' => ENV['ENABLE_ZSH'] }
      
    end
  end
  clients=2
  ram_client=2048
  cpu_client=2
  (1..clients).each do |i|
    config.vm.define "mediawiki#{i}" do |mediawiki|
      # mediawiki.vm.box = "debian/contrib-buster64"
      # test bullseye
      mediawiki.vm.box = "debian/bullseye64"
      mediawiki.vm.network "private_network", type: "static", ip: "192.168.99.3#{i}"
      mediawiki.vm.hostname = "mediawiki#{i}"
      mediawiki.vm.provider "virtualbox" do |v|
        v.name = "mediawiki#{i}"
        v.memory = ram_client
        v.cpus = cpu_client
      end
      mediawiki.vm.provision :shell do |shell|
        shell.path = "install_mediawiki.sh"
        shell.args = ["node#{i}", "192.168.99.10"]
      end
    end
  end
end