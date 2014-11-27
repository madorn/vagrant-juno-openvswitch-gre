OpenStack Juno Deployment with Vagrant (Open vSwitch + GRE)
==============================================================
Features
------------
* Three Nodes (Controller, Network, Compute) - Ubuntu 14.04
* Open vSwitch with GRE tunneling
* Works with VMware Fusion or VirtualBox
* Network node includes internet gateway (eth2 buried into br-ex ovs bridge)

Minimum Requirements
---------------------
* [Vagrant](http://www.vagrantup.com)
* 8GB hard drive space
* At least 3GB available RAM

Get Started
------------
**Clone the Git repo** <br /> 
``git clone https://github.com/madorn//vagrant-juno-openvswitch-gre.git`` <br /> 

**For VirtualBox** <br />
Verify that you have default host-only vboxnet0 network (192.168.56.0/24) <br /> 
``vagrant up --provider virtualbox --provision``

**For VMware Fusion** <br />
Verify that you have default host-only vmnet1 network (172.16.99.0/24) <br /> 
``vagrant up --provider vmware_fusion --provision``

**Creating an external network for the internet gateway  (br-ex)**
``neutron net-create public-net --router:external True --provider:network_type flat --provider:physical_network physnet1``
``neutron subnet-create --gateway --allocation-pool start=10.0.0.0,end=10.0.0.0 --disable-dhcp public-subnet 10.0.0.0/24``
