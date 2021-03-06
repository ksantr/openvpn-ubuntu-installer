#!/bin/bash

echo -e "
###############################
#####  OpenVPN installer  #####  
#####  github.com/ksantr  #####  
###############################
\nAttention! Script was tested only on Ubuntu 14.04.\n"

# Check os
os=$( cat /etc/issue | grep -i ubuntu > /dev/null; echo $? );
if [[ "$os" -ne 0 ]]; then echo "This is not Ubuntu."; exit 0; fi

# Client's and server's names
echo -n "Type the client name for cert name (Empty for default name): "
read client
if [[ -z "$client" ]]; then client="client1";fi
echo -n "Type the server name (Empty for default name): "
read server

# VPN ip address
if [[ -z "$server" ]]; then server="server";fi
echo -n "Type the openvpn ip address: "
read vpn_ip
if [[ -z "$vpn_ip" ]]; then echo "Empty ip"; exit 0;fi

# Port
echo -n "Type the openvpn port (Empty for default 1194): "
read port
if [[ -z "$port" ]]; then port="1194"; fi

# Network
echo -n "OpenVPN network (Empty for default 10.8.0.0/8): "
read network
if [[ -z "$network" ]]; then network="10.8.0.0/8"; fi

# firewall settings setting
ufw=0
while [[ "$ufw" != "y" && "$ufw" != "n" ]]; do
echo -n "Use ufw for firewall settings (y/n): "
read ufw;done

# ipv6 settings
ipv6=0
while [[ "$ipv6" != "y" && "$ipv6" != "n" ]]; do
echo -n "Disable ipv6 (y/n): "
read ipv6; done

echo "
################################## 
####  Install needed packets  ####  
##################################
"

sudo apt-get update && sudo apt-get upgrade -y
sudo apt-get install openvpn easy-rsa unzip -y
if [[ "$ufw" = "y" ]]; then
    sudo apt-get install ufw -y;
fi

sudo chmod 777 /etc/openvpn/
# OpenVPN Configuration
gunzip -c /usr/share/doc/openvpn/examples/sample-config-files/server.conf.gz > /etc/openvpn/server.conf
sed -i "s/port 1194/port $port/" /etc/openvpn/server.conf
#sed -i "s/;local a.b.c.d/local $vpn_ip/" /etc/openvpn/server.conf
sed -i 's/dh1024.pem/dh2048.pem/' /etc/openvpn/server.conf
sed -i 's/;push "redirect-gateway def1/push "redirect-gateway def1/' /etc/openvpn/server.conf
sed -i 's/;push "dhcp-option DNS/push "dhcp-option DNS/' /etc/openvpn/server.conf
sed -i 's/;user nobody/user nobody/' /etc/openvpn/server.conf
sed -i 's/;group nogroup/group nogroup/' /etc/openvpn/server.conf
sed -i 's/;cipher DES-EDE3-CBC/cipher DES-EDE3-CBC/' /etc/openvpn/server.conf
# Packet Forwarding
sudo sysctl net.ipv4.ip_forward=1

if [[ "$ipv6" = "y" ]]; then
    echo 
    # Disable ipv6
    sudo sysctl net.ipv6.conf.all.disable_ipv6=1
    sudo sysctl net.ipv6.conf.default.disable_ipv6=1
    sudo sysctl net.ipv6.conf.lo.disable_ipv6=1
    # Apply rules
    echo "[!] ipv6 disabled"
fi

sudo sysctl -p; 

if [[ "$ufw" = "y" ]]; then
    echo "
    ################################## 
    #####    UFW configuration    ####  
    ##################################
    "
    sudo ufw allow ssh
    sudo ufw allow $port/udp
    sudo sed -i 's/DEFAULT_FORWARD_POLICY="DROP"/DEFAULT_FORWARD_POLICY="ACCEPT"/' /etc/default/ufw
    sudo sed -i 1i"# START OPENVPN RULES" /etc/ufw/before.rules
    sudo sed -i 2i"# NAT table rules" /etc/ufw/before.rules
    sudo sed -i 3i"*nat" /etc/ufw/before.rules
    sudo sed -i 4i":POSTROUTING ACCEPT [0:0]" /etc/ufw/before.rules
    sudo sed -i 5i"# Allow traffic from OpenVPN client to eth0" /etc/ufw/before.rules
    sudo sed -i 6i"-A POSTROUTING -s $network -o eth0 -j MASQUERADE" /etc/ufw/before.rules
    sudo sed -i 7i"COMMIT" /etc/ufw/before.rules
    sudo sed -i 8i"# END OPENVPN RULES" /etc/ufw/before.rules
    echo -e "\n[!] Firewall enabling:"
    sudo ufw enable
    sudo ufw status;
fi

echo "
################################## 
###  Prepare keys generation.  ### 
##################################
"
cp -r /usr/share/easy-rsa/ /etc/openvpn
mkdir /etc/openvpn/easy-rsa/keys
cd /etc/openvpn/easy-rsa
source vars

echo "
################################## 
#####  Generate server keys  #####  
##################################
"
./clean-all
./build-dh
./pkitool --initca
./pkitool --server $server
cp /etc/openvpn/easy-rsa/keys/{server.crt,server.key,ca.crt,dh2048.pem} /etc/openvpn


echo "
################################## 
###  Generate keys for client ####  
##################################
"
./pkitool $client
mkdir /tmp/$client && cp /etc/openvpn/easy-rsa/keys/{$client.crt,$client.key,ca.crt} /tmp/$client
cp /usr/share/doc/openvpn/examples/sample-config-files/client.conf /tmp/$client/client.ovpn
sed -i "s/remote my-server-1 1194/remote $vpn_ip $port/" /tmp/$client/client.ovpn
sed -i "s/client.crt/$client.crt/" /tmp/$client/client.ovpn
sed -i "s/client.key/$client.key/" /tmp/$client/client.ovpn
sed -i 's/;cipher x/cipher DES-EDE3-CBC/' /tmp/$client/client.ovpn	

# DNS fix
echo "script-security 2" >> /tmp/$client/client.ovpn
echo "up /etc/openvpn/update-resolv-conf" >> /tmp/$client/client.ovpn
echo "down /etc/openvpn/update-resolv-conf" >> /tmp/$client/client.ovpn

cd /etc/openvpn/ && sudo rm -rf /etc/openvpn/easy-rsa/
sudo update-rc.d openvpn defaults > /dev/null;
sudo chmod 755 /etc/openvpn/;
sudo service openvpn start > /dev/null;
if pgrep openvpn > /dev/null; then 
echo "
################################## 
###       OpenVPN started      ###
##################################
"
echo "Copy securelly client's files from /tmp/$client to the client's machine"; 
echo "
################################## 
####  Installation finished.  ####
##################################
"
fi
