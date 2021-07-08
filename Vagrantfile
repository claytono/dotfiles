# -*- mode: ruby -*-
# vi: set ft=ruby :

Vagrant.configure("2") do |config|
  # Named stub here so that box specific provisioners can run things before setup.sh
  config.vm.provision "prep",
    type: "shell",
    inline: "true"

  config.vm.define "macos" do |macos|
    macos.vm.box = "monsenso/macos-10.13"
  end

  config.vm.define "debian" do |debian|
    debian.vm.box = "debian/buster64"
    debian.vm.provision "prep", type: "shell", privileged: true,
      preserve_order: true,
      inline: "apt-get update; apt-get install curl -y"
  end

  config.vm.provision "bootstrap", type: "shell", privileged: false,
    inline: "bash -xve /vagrant/script/bootstrap"
end
