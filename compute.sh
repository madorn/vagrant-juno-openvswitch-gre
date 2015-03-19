#!/bin/bash -eux

### Configuration

ETH1=`hostname -I | cut -f2 -d' '`

if [ $ETH1 = 192.168.56.58 ];then
export MY_IP=192.168.56.58
export RABBITMQ_IP=192.168.56.56
export MYSQL_IP=192.168.56.56
export KEYSTONE_IP=192.168.56.56
export GLANCE_IP=192.168.56.56
export NEUTRON_IP=192.168.56.56
export NOVA_IP=192.168.56.56
export CINDER_IP=192.168.56.56
export HORIZON_IP=192.168.56.56
else
export MY_IP=172.16.99.102
export RABBITMQ_IP=172.16.99.100
export MYSQL_IP=172.16.99.100
export KEYSTONE_IP=172.16.99.100
export GLANCE_IP=172.16.99.100
export NEUTRON_IP=172.16.99.100
export NOVA_IP=172.16.99.100
export CINDER_IP=172.16.99.100
export HORIZON_IP=172.16.99.100
fi

### Synchronize time

ntpdate -u ntp.ubuntu.com | true

apt-get update

apt-get install -y ubuntu-cloud-keyring software-properties-common

add-apt-repository -y cloud-archive:juno

apt-get update

### Neutron

apt-get install -y openvswitch-switch neutron-plugin-openvswitch-agent

service neutron-plugin-openvswitch-agent stop

modprobe gre
modprobe openvswitch

service openvswitch-switch restart

export SERVICE_TOKEN=ADMIN
export SERVICE_ENDPOINT=http://$KEYSTONE_IP:35357/v2.0

export SERVICE_TENANT_ID=`keystone tenant-get Services | awk '/ id / { print $4 }'`

sed -i "s|connection = sqlite:////var/lib/neutron/neutron.sqlite|connection = mysql://neutron:notneutron@$MYSQL_IP/neutron|g" /etc/neutron/neutron.conf
sed -i "s/#rabbit_host=localhost/rabbit_host=$RABBITMQ_IP/g" /etc/neutron/neutron.conf
sed -i 's/# allow_overlapping_ips = False/allow_overlapping_ips = True/g' /etc/neutron/neutron.conf
sed -i 's/# service_plugins =/service_plugins = router/g' /etc/neutron/neutron.conf
sed -i 's/# auth_strategy = keystone/auth_strategy = keystone/g' /etc/neutron/neutron.conf
sed -i "s/auth_host = 127.0.0.1/auth_host = $KEYSTONE_IP/g" /etc/neutron/neutron.conf
sed -i 's/%SERVICE_TENANT_NAME%/Services/g' /etc/neutron/neutron.conf
sed -i 's/%SERVICE_USER%/neutron/g' /etc/neutron/neutron.conf
sed -i 's/%SERVICE_PASSWORD%/notneutron/g' /etc/neutron/neutron.conf
sed -i "s|# nova_url = http://127.0.0.1:8774\(\/v2\)\?|nova_url = http://$NOVA_IP:8774/v2|g" /etc/neutron/neutron.conf
sed -i "s/# nova_admin_username =/nova_admin_username = nova/g" /etc/neutron/neutron.conf
sed -i "s/# nova_admin_tenant_id =/nova_admin_tenant_id = $SERVICE_TENANT_ID/g" /etc/neutron/neutron.conf
sed -i "s/# nova_admin_password =/nova_admin_password = notnova/g" /etc/neutron/neutron.conf
sed -i "s|# nova_admin_auth_url =|nova_admin_auth_url = http://$KEYSTONE_IP:35357/v2.0|g" /etc/neutron/neutron.conf

# Configure Neutron ML2
sed -i 's|# type_drivers = local,flat,vlan,gre,vxlan|type_drivers = flat,gre|g' /etc/neutron/plugins/ml2/ml2_conf.ini
sed -i 's|# tenant_network_types = local|tenant_network_types = flat,gre|g' /etc/neutron/plugins/ml2/ml2_conf.ini
sed -i 's|# mechanism_drivers =|mechanism_drivers = openvswitch,l2population|g' /etc/neutron/plugins/ml2/ml2_conf.ini
sed -i 's|# flat_networks =|flat_networks = physnet1|g' /etc/neutron/plugins/ml2/ml2_conf.ini
sed -i 's|# tunnel_id_ranges =|tunnel_id_ranges = 1:1000|g' /etc/neutron/plugins/ml2/ml2_conf.ini
sed -i 's|# enable_security_group = True|firewall_driver = neutron.agent.linux.iptables_firewall.OVSHybridIptablesFirewallDriver\nenable_security_group = True|g' /etc/neutron/plugins/ml2/ml2_conf.ini

# Configure Neutron ML2 continued...
( cat | tee -a /etc/neutron/plugins/ml2/ml2_conf.ini ) <<EOF

[ovs]
local_ip = $MY_IP
tunnel_type = gre
enable_tunneling = True
physical_interface_mappings = physnet1:br-ex

[agent]
l2_population = True
tunnel_types = gre
physical_interface_mappings = physnet1:br-ex

[l2pop]
agent_boot_time = 180
EOF

service neutron-plugin-openvswitch-agent start

### Nova

if egrep 'vmx|svm' /proc/cpuinfo  > /dev/null 2>&1 ; then
apt-get install -y nova-compute
modprobe kvm
modprobe kvm_intel
cat <<EOF | tee -a /etc/modules
kvm
kvm_intel
EOF
else
apt-get install -y nova-compute-qemu
fi

cat <<EOF | tee -a /etc/nova/nova.conf
network_api_class=nova.network.neutronv2.api.API
neutron_url=http://$NEUTRON_IP:9696
neutron_auth_strategy=keystone
neutron_admin_tenant_name=Services
neutron_admin_username=neutron
neutron_admin_password=notneutron
neutron_admin_auth_url=http://$KEYSTONE_IP:35357/v2.0
firewall_driver=nova.virt.firewall.NoopFirewallDriver
security_group_api=neutron
linuxnet_interface_driver=nova.network.linux_net.LinuxOVSInterfaceDriver
rabbit_host=$RABBITMQ_IP
glance_host=$GLANCE_IP
auth_strategy=keystone
force_config_drive=always
my_ip=$MY_IP
fixed_ip_disassociate_timeout=30
enable_instance_password=False
service_neutron_metadata_proxy=True
neutron_metadata_proxy_shared_secret=openstack
novncproxy_base_url=http://$HORIZON_IP:6080/vnc_auto.html
vncserver_proxyclient_address=$MY_IP
vncserver_listen=0.0.0.0

[database]
connection=mysql://nova:notnova@$MYSQL_IP/nova

[keystone_authtoken]
auth_uri = http://$KEYSTONE_IP:5000
auth_host = $KEYSTONE_IP
auth_port = 35357
auth_protocol = http
admin_tenant_name = Services
admin_user = nova
admin_password = notnova
EOF

service nova-compute start

### Cinder

apt-get install -y cinder-volume

service cinder-volume stop
service tgt stop

( cat | tee -a /etc/tgt/targets.conf ) <<EOF
default-driver iscsi
EOF
( cat | tee -a /etc/cinder/cinder.conf ) <<EOF
my_ip = $MY_IP
rabbit_host = $RABBITMQ_IP
glance_host = $GLANCE_IP
control_exchange = cinder
notification_driver = cinder.openstack.common.notifier.rpc_notifier
enabled_backends=cinder-volumes-sata-backend,cinder-volumes-ssd-backend

[database]
connection = mysql://cinder:notcinder@$MYSQL_IP/cinder

[cinder-volumes-sata-backend]
volume_group=cinder-volumes-sata
volume_driver=cinder.volume.drivers.lvm.LVMISCSIDriver
volume_backend_name=sata

[cinder-volumes-ssd-backend]
volume_group=cinder-volumes-ssd
volume_driver=cinder.volume.drivers.lvm.LVMISCSIDriver
volume_backend_name=ssd

[keystone_authtoken]
auth_uri = http://$KEYSTONE_IP:5000
auth_host = $KEYSTONE_IP
auth_port = 35357
auth_protocol = http
admin_tenant_name = Services
admin_user = cinder
admin_password = notcinder
EOF

CINDER0="/opt/cinder0.img"
CINDER1="/opt/cinder1.img"
LOOP0=$(losetup -f)
dd if=/dev/zero of=${CINDER0} bs=1 count=0 seek=1000G
losetup ${LOOP0} ${CINDER0}
LOOP1=$(losetup -f)
dd if=/dev/zero of=${CINDER1} bs=1 count=0 seek=1000G
losetup ${LOOP1} ${CINDER1}
pvcreate ${LOOP0}
pvcreate ${LOOP1}
vgcreate cinder-volumes-sata ${LOOP0}
vgcreate cinder-volumes-ssd ${LOOP1}
pvscan

service tgt start
service cinder-volume start
