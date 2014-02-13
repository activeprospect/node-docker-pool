# -*- mode: ruby -*-
# vi: set ft=ruby :


Vagrant::Config.run do |config|
  config.vm.box = 'ubuntu'
  config.vm.box_url = 'http://files.vagrantup.com/precise64.box'
end

Vagrant.configure("2") do |config|

  config.vm.provision "docker", images: ["ubuntu"]

  config.vm.provision "shell", inline: <<-BASH
    echo "deb http://archive.ubuntu.com/ubuntu precise universe" >> /etc/apt/sources.list
    apt-get update
    apt-get install -y python-software-properties python g++ make
    add-apt-repository ppa:chris-lea/node.js
    apt-get update
    apt-get install -y nodejs
    cd /vagrant
    npm install
  BASH

  config.vm.provider "virtualbox" do |vm|
    vm.customize ["modifyvm", :id, "--memory", "5104"]
  end
end
