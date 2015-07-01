#!/bin/sh

cd /etc/openvpn/easy-rsa
source ./vars > /dev/null
./clean-all

#copy stdout to fd 3
exec 3>&1
exec >/dev/null 2>&1

#create root ca
expect -c "
set timeout 2
spawn /etc/openvpn/easy-rsa/build-ca
expect \"Country Name (2 letter code) \[JP\]:\"
send \"\r\"
expect \"State or Province Name (full name) \[CA\]:\"
send \"\r\"
expect \"Locality Name (eg, city) \[Tokyo\]:\"
send \"\r\"
expect \"Organization Name (eg, company) \[PrimeCloud-Controller-ORG\]:\"
send \"\r\"
expect \"Organizational Unit Name (eg, section) \[\]:\"
send \"\r\"
expect \"Common Name (eg, your name or your server's hostname) \[PrimeCloud-Controller-ORG CA\]:\"
send \"\r\"
expect \"Name \[\]:\"
send \"\r\"
expect \"Email Address \[mail@pcc01.dev.primecloud-controller.org\]:\"
send \"\r\"
interact"

cp /etc/openvpn/easy-rsa/keys/ca.crt /etc/openvpn/

#create server certificate
expect -c "
set timeout 2
spawn /etc/openvpn/easy-rsa/build-key-server server
expect \"Country Name (2 letter code) \[JP\]:\"
send \"\r\"
expect \"State or Province Name (full name) \[CA\]:\"
send \"\r\"
expect \"Locality Name (eg, city) \[Tokyo\]:\"
send \"\r\"
expect \"Organization Name (eg, company) \[PrimeCloud-Controller-ORG\]:\"
send \"\r\"
expect \"Organizational Unit Name (eg, section) \[\]:\"
send \"\r\"
expect \"Common Name (eg, your name or your server's hostname) \[PrimeCloud-Controller-ORG CA\]:\"
send \"\r\"
expect \"Name \[\]:\"
send \"\r\"
expect \"Email Address \[mail@pcc01.dev.primecloud-controller.org\]:\"
send \"\r\"
expect \"A challenge password \[\]:\"
send \"\r\"
expect \"An optional company name \[\]:\"
send \"\r\"
expect \"Sign the certificate? \[y/n\]:\"
send \"y\r\"
expect \"1 out of 1 certificate requests certified, commit? \[y/n\]:\"
send \"y\r\"
interact"

cp /etc/openvpn/easy-rsa/keys/server.crt /etc/openvpn
cp /etc/openvpn/easy-rsa/keys/server.key /etc/openvpn

#create Diffie-Hellman key
/etc/openvpn/easy-rsa/build-dh
cp /etc/openvpn/easy-rsa/keys/dh1024.pem /etc/openvpn/

#create TLS key
openvpn --genkey --secret /etc/openvpn/ta.key

#create crl
expect -c "
set timeout 2
spawn /etc/openvpn/easy-rsa/build-key dummy
expect \"Country Name (2 letter code) \[JP\]:\"
send \"\r\"
expect \"State or Province Name (full name) \[CA\]:\"
send \"\r\"
expect \"Locality Name (eg, city) \[Tokyo\]:\"
send \"\r\"
expect \"Organization Name (eg, company) \[PrimeCloud-Controller-ORG\]:\"
send \"\r\"
expect \"Organizational Unit Name (eg, section) \[\]:\"
send \"\r\"
expect \"Common Name (eg, your name or your server's hostname) \[PrimeCloud-Controller-ORG CA\]:\"
send \"\r\"
expect \"Name \[\]:\"
send \"\r\"
expect \"Email Address \[mail@pcc01.dev.primecloud-controller.org\]:\"
send \"\r\"
expect \"A challenge password \[\]:\"
send \"\r\"
expect \"An optional company name \[\]:\"
send \"\r\"
expect \"Sign the certificate? \[y/n\]:\"
send \"y\r\"
expect \"1 out of 1 certificate requests certified, commit? \[y/n\]:\"
send \"y\r\"
interact"

./revoke-full dummy
cp /etc/openvpn/easy-rsa/keys/crl.pem /etc/openvpn/

#create clinent certificate
expect -c "
set timeout 2
spawn /etc/openvpn/easy-rsa/build-key ec2-vpnclient
expect \"Country Name (2 letter code) \[JP\]:\"
send \"\r\"
expect \"State or Province Name (full name) \[CA\]:\"
send \"\r\"
expect \"Locality Name (eg, city) \[Tokyo\]:\"
send \"\r\"
expect \"Organization Name (eg, company) \[PrimeCloud-Controller-ORG\]:\"
send \"\r\"
expect \"Organizational Unit Name (eg, section) \[\]:\"
send \"\r\"
expect \"Common Name (eg, your name or your server's hostname) \[PrimeCloud-Controller-ORG CA\]:\"
send \"\r\"
expect \"Name \[\]:\"
send \"\r\"
expect \"Email Address \[mail@pcc01.dev.primecloud-controller.org\]:\"
send \"\r\"
expect \"A challenge password \[\]:\"
send \"\r\"
expect \"An optional company name \[\]:\"
send \"\r\"
expect \"Sign the certificate? \[y/n\]:\"
send \"y\r\"
expect \"1 out of 1 certificate requests certified, commit? \[y/n\]:\"
send \"y\r\"
interact"

cp /etc/openvpn/easy-rsa/keys/ec2-vpnclient.key /etc/openvpn/

#set nonpassword clinent certificate
openssl rsa -in /etc/openvpn/easy-rsa/keys/ec2-vpnclient.key -out keys/ec2-vpnclient.key.nopass

#create client.conf
cat << EOF > /etc/openvpn/easy-rsa/keys/client.conf
client
dev tun
proto udp
resolv-retry infinite
nobind
persist-key
persist-tun
ca ca.crt
cert aws-vpnclient.crt
key aws-vpnclient.key.nopass
ns-cert-type server
tls-auth ta.key 1
comp-lzo
verb 3
auth-user-pass
keepalive 10 60
fragment 1426
mssfix
EOF


#create startup/shutdown script for vpn client
touch /etc/openvpn/easy-rsa/keys/openvpn-startup /etc/openvpn/easy-rsa/keys/openvpn-shutdown
chmod a+x /etc/openvpn/easy-rsa/keys/openvpn-startup /etc/openvpn/easy-rsa/keys/openvpn-shutdown




#copy credential set for vpn client
mkdir -p /etc/openvpn/easy-rsa/keys/client && cd keys
cp ca.crt ec2-vpnclient.crt client.conf ec2-vpnclient.key.nopass openvpn-startup openvpn-shutdown /etc/openvpn/ta.key client

#swtich stdout fd 1
exec 1>&3 2>&1

exit 0

