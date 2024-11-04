
#!/bin/bash
#
# https://github.com/Nyr/openvpn-install
#
# This script sets up OpenVPN with specified client requirements.
# Auth is set to SHA1, cipher to AES-256-CBC, and unnecessary tls-crypt is removed.

# Detect Debian users running the script with "sh" instead of bash
if readlink /proc/$$/exe | grep -q "dash"; then
	echo 'This installer needs to be run with "bash", not "sh".'
	exit
fi

# Discard stdin. Needed when running from a one-liner which includes a newline
read -N 999999 -t 0.001

# Detect OS
if grep -qs "ubuntu" /etc/os-release; then
	os="ubuntu"
	group_name="nogroup"
elif [[ -e /etc/debian_version ]]; then
	os="debian"
	group_name="nogroup"
elif [[ -e /etc/almalinux-release || -e /etc/rocky-release || -e /etc/centos-release ]]; then
	os="centos"
	group_name="nobody"
elif [[ -e /etc/fedora-release ]]; then
	os="fedora"
	group_name="nobody"
else
	echo "This installer seems to be running on an unsupported distribution."
	exit
fi

if [[ "$EUID" -ne 0 ]]; then
	echo "This installer needs to be run with superuser privileges."
	exit
fi

if [[ ! -e /dev/net/tun ]] || ! ( exec 7<>/dev/net/tun ) 2>/dev/null; then
	echo "The system does not have the TUN device available. TUN must be enabled."
	exit
fi

new_client () {
	# Generates the custom client.ovpn with specified modifications
	{
	cat /etc/openvpn/server/client-common.txt
	echo "<ca>"
	cat /etc/openvpn/server/easy-rsa/pki/ca.crt
	echo "</ca>"
	echo "<cert>"
	sed -ne '/BEGIN CERTIFICATE/,$ p' /etc/openvpn/server/easy-rsa/pki/issued/"$client".crt
	echo "</cert>"
	echo "<key>"
	cat /etc/openvpn/server/easy-rsa/pki/private/"$client".key
	echo "</key>"
	} > ~/"$client".ovpn
}

# Configuration continues in subsequent parts

if [[ ! -e /etc/openvpn/server/server.conf ]]; then
	# Prompt for essential settings
	clear
	echo 'Welcome to this OpenVPN installer!'

	# Network details
	echo "What port should OpenVPN listen to?"
	read -p "Port [1196]: " port
	[[ -z "$port" ]] && port="1196"

	# Enter a client name
	echo "Enter a name for the client:"
	read -p "Client name [client]: " client
	[[ -z "$client" ]] && client="client"

	# Install packages and setup
	apt-get update && apt-get install -y openvpn openssl ca-certificates

	# Configure server.conf with SHA1 auth, AES-256-CBC cipher
	echo "local 0.0.0.0
port $port
proto tcp
dev tun
ca ca.crt
cert server.crt
key server.key
dh none
auth SHA1                # Modified from SHA512 to SHA1
cipher AES-256-CBC       # Set AES-256-CBC as encryption
topology subnet
server 10.8.0.0 255.255.255.0" > /etc/openvpn/server/server.conf

	# DNS settings and firewall rules
	echo 'push "block-outside-dns"' >> /etc/openvpn/server/server.conf
	echo "keepalive 10 120
user nobody
group $group_name
persist-key
persist-tun
verb 3" >> /etc/openvpn/server/server.conf

	# Generate client-common.txt with updated options
	echo "client
dev tun
proto tcp
remote 0.0.0.0 $port
resolv-retry infinite
nobind
persist-key
persist-tun
remote-cert-tls server
auth SHA1
cipher AES-256-CBC
ignore-unknown-option block-outside-dns
block-outside-dns
verb 3" > /etc/openvpn/server/client-common.txt

	# Enable and start the OpenVPN service
	systemctl enable --now openvpn-server@server.service
	new_client
fi
