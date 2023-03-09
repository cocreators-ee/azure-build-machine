# Allocate all CPU cores to the VM
if RbConfig::CONFIG['host_os'] =~ /darwin/
    CPUS = `sysctl -n hw.ncpu`.to_i
elsif RbConfig::CONFIG['host_os'] =~ /linux/
    CPUS = `nproc`.to_i
else  # Windows 🤞
    CPUS = `wmic cpu get NumberOfCores`.split("\n")[2].to_i
end

RAM_MB = 4096
# CPUS = 8  # Or override manually if you want

Vagrant.configure("2") do |cfg|
    cfg.vm.box = "generic/ubuntu-2204"

    # If you could pass args from vagrant CLI this might work
    # cfg.vm.provision "shell", path: "setup.sh"

    unless Vagrant.has_plugin?("vagrant-disksize")
        raise  Vagrant::Errors::VagrantError.new, "vagrant-disksize plugin is missing. Please install it using 'vagrant plugin install vagrant-disksize' and rerun 'vagrant up'"
    end

    cfg.disksize.size = '50GB'
    vm_name = "build-vm"
    cfg.vm.define vm_name do |s|
        s.vm.network "private_network", ip: "172.26.26.26"
        s.vm.hostname = vm_name
        s.vm.synced_folder ".", "/src"
        s.vm.provider "virtualbox" do |vbox|
            vbox.name = vm_name
            vbox.customize ["modifyvm", :id, "--memory", RAM_MB]
            vbox.customize ["modifyvm", :id, "--cpus", CPUS]
            vbox.customize ["modifyvm", :id, "--cpuexecutioncap", 75]
            vbox.customize ["modifyvm", :id, "--ioapic", "on"]
        end
    end
end