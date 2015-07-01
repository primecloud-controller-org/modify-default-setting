#!/bin/sh

##########################################################
#DEFAULT_HOSTNAME="pcc01.dev.primecloud-controller.org"
#DEFAULT_DNSNAME="dev.primecloud-controller.org"
##########################################################



DIR=`dirname $0`
cd ${DIR}
BASE_DIR=`pwd`
cd ${BASE_DIR}


#Get meta-data
MAC=`curl -s -f http://169.254.169.254/latest/meta-data/mac/`
LOCAL_NETWORK=`curl -s -f http://169.254.169.254/latest/meta-data/network/interfaces/macs/$MAC/vpc-ipv4-cidr-block`
PUBLICIP=`curl -s -f http://169.254.169.254/latest/meta-data/network/interfaces/macs/$MAC/ipv4-associations/`
SUBNET_ID=`curl -s -f http://169.254.169.254/latest/meta-data/network/interfaces/macs/$MAC/subnet-id/`
VPC_ID=`curl -s -f http://169.254.169.254/latest/meta-data/network/interfaces/macs/$MAC/vpc-id/`
AVAILABILITY_ZONE=`curl -s -f http://169.254.169.254/latest/meta-data/placement/availability-zone/`


if [ ! -n "${LOCAL_NETWORK}" ]; then
        echo "Cannot Get vpc-ipv4-cider-block"
        exit 1
fi

if [ ! -n "${PUBLICIP}" ]; then
        echo "Cannot Get ipv4-associations"
        exit 1
fi
if [ ! -n "${SUBNET_ID}" ]; then
        echo "Cannot Get subnet-id"
        exit 1
fi
if [ ! -n "${VPC_ID}" ]; then
        echo "Cannot Get vpc-id"
        exit 1
fi
if [ ! -n "${AVAILABILITY_ZONE}" ]; then
        echo "Cannot Get availability-zone"
        exit 1
fi

#GET Client.zip password
CLIENT_ZIP_PASS=`mkpasswd -l 12`
if [ ! -n "${CLIENT_ZIP_PASS}" ]; then
        echo "Cannot Get CLIENT_ZIP_PASS"
        exit 1
fi


#Read parameter settings
SET_ENV=${BASE_DIR}/modifyParameter.sh

if [ ! -f ${SET_ENV} ]; then
  echo "${SET_ENV}: No such file"
  exit 1
fi
. ${SET_ENV}



#
#
#Set /var/named/chroot/etc/name.conf
echo "[ 1/10] Set bind parameters"

NODE_NAME=`hostname -s`
sed -i -e "s/dev.primecloud-controller.org/$DOMAIN_NAME/" /var/named/chroot/etc/named.conf

sed -i -e "s/dev.primecloud-controller.org/$DOMAIN_NAME/g" /var/named/chroot/etc/named/dev.primecloud-controller.org.zone
sed -i -e "s/pcc01/$NODE_NAME/g" /var/named/chroot/etc/named/dev.primecloud-controller.org.zone
if [ ! -f /var/named/chroot/etc/named/$DOMAIN_NAME.zone ]; then
	cp /var/named/chroot/etc/named/dev.primecloud-controller.org.zone /var/named/chroot/etc/named/$DOMAIN_NAME.zone
fi

sed -i -e "s/dev.primecloud-controller.org/$DOMAIN_NAME/g" /var/named/chroot/etc/named/dev.primecloud-controller.org.local.rev
sed -i -e "s/pcc01/$NODE_NAME/g" /var/named/chroot/etc/namede/dev.primecloud-controller.org.rev
if [ ! -f /var/named/chroot/etc/named/$DOMAIN_NAME.local.rev ]; then
	cp /var/named/chroot/etc/named/dev.primecloud-controller.org.rev /var/named/chroot/etc/named/$DOMAIN_NAME.local.rev
fi

sed -i -e "s/dev.primecloud-controller.org/$DOMAIN_NAME/g" /var/named/chroot/etc/named/dev.primecloud-controller.org.vpc.rev
sed -i -e "s/pcc01/$NODE_NAME/g" /var/named/chroot/etc/named/dev.primecloud-controller.org.vpc.rev
if [ ! -f /var/named/chroot/etc/named/$DOMAIN_NAME.vpc.rev ]; then
	cp /var/named/chroot/etc/named/dev.primecloud-controller.org.vpc.rev /var/named/chroot/etc/named/$DOMAIN_NAME.vpc.rev
fi

sed -i -e "s/dev.primecloud-controller.org/$DOMAIN_NAME/g" /var/named/chroot/etc/named/localhost.rev
sed -i -e "s/pcc01/$NODE_NAME/g" /var/named/chroot/etc/named/localhost.rev

/etc/init.d/named start > /dev/null 2>&1
if [ $? -ne 0 ]; then
	echo "Error: Set bind parameters failed"
	exit 1
fi


echo "[ 2/10] Set tomcat user password"
#Set tomcat user password
echo "tomcat:${TOMCAT_PASS}" | /usr/sbin/chpasswd -c MD5 >/dev/null 2>&1


echo "[ 3/10] Set puppet parameters"
#Create fileserver.conf for puppet-server
sed -i -e "s/^\([^#].*\)allow \*\..*/\1allow \*\.${DOMAIN_NAME}/" /etc/puppet/fileserver.conf

#Create namespaceauth.conf for puppet-server
sed -i -e "s/^\([^#].*\)allow \*\..*/\1allow \*\.${DOMAIN_NAME}/" /etc/puppet/namespaceauth.conf

#Set puppetmaster fqdn
sed -i -e "s/\(\$zabbix_server *= \)\"[^\$].*\"/\1\"${HOST_NAME}\"/" /etc/puppet/manifests/templates/basenode.pp
sed -i -e "s/\(\$rsyslog_log_server *= \)\"[^\$].*\"/\1\"${HOST_NAME}\"/" /etc/puppet/manifests/templates/basenode.pp

#Set autosign.conf
cat > /etc/puppet/autosign.conf << AUTOSIGN_CONF_EOF
*.${DOMAIN_NAME}
AUTOSIGN_CONF_EOF

/etc/init.d/puppetmaster start >/dev/null 2>&1
sleep 5

# Enable autosign
/etc/init.d/puppetmaster stop > /dev/null 2>&1
sleep 5

chown tomcat:tomcat /etc/puppet/manifests/site.pp
chown tomcat:tomcat /etc/puppet/manifests/auto


#
#set mysql
echo "[ 4/10] Set database password"
/etc/init.d/mysqld start > /dev/null 2>&1
sleep 20

mysqladmin -uroot --password="${MYSQL_ROOT_PASS}" status > /dev/null 2>&1
if [ $? -ne 0 ]; then
        /etc/init.d/mysqld stop > /dev/null 2>&1
        sleep 20
        /usr/bin/mysqld_safe --user=root --skip-grant-tables > /dev/null  2>&1 &
        sleep 20

        mysql -uroot <<PASSWORD_RECOVERY
update mysql.user set password=password('${MYSQL_ROOT_PASS}') where user='root';
flush privileges;
PASSWORD_RECOVERY
/etc/init.d/mysqld stop >/dev/null 2>&1
        sleep 20
        /etc/init.d/mysqld start >/dev/null 2>&1
        sleep 20
fi

mysqladmin -uroot --password="${MYSQL_ROOT_PASS}" status >/dev/null 2>&1

if [ $? -ne 0 ]; then
        echo "Error: Set MYSQL root password failed"
        exit 1
fi


mysql -uroot -p${MYSQL_ROOT_PASS}<< SET_ADC_USER_PASS_EOF
SET PASSWORD FOR ${ADC_DATABASE_USER}@'localhost' = password('${ADC_DATABASE_PASS}');
SET PASSWORD FOR ${ADC_DATABASE_USER}@'%' = password('${ADC_DATABASE_PASS}');
SET_ADC_USER_PASS_EOF

if [ $? -ne 0 ]; then
    echo "Error: Set adc database password failed"
    exit 1
fi

mysql -uroot -p${MYSQL_ROOT_PASS}<< SET_ZABBIX_USER_PASS_EOF
SET PASSWORD FOR ${ZABBIX_DATABASE_USER}@'localhost' = password('${ZABBIX_DATABASE_PASS}');
SET PASSWORD FOR ${ZABBIX_DATABASE_USER}@'%' = password('${ZABBIX_DATABASE_PASS}');
SET_ZABBIX_USER_PASS_EOF

if [ $? -ne 0 ]; then
        echo "Error: Set zabbix database password  failed"
        exit 1
fi

#Set defaultVPC parameters
mysql -uadc -p${ADC_DATABASE_USER} -p${ADC_DATABASE_PASS} adc -e "UPDATE AWS_CERTIFICATE SET AWS_ACCESS_ID='${AWS_ACCESS_ID}',AWS_SECRET_KEY='${AWS_SECRET_KEY}',DEF_SUBNET='${SUBNET_ID}',DEF_LB_SUBNET='${SUBNET_ID}' WHERE PLATFORM_NO=1;"
mysql -uadc -p${ADC_DATABASE_USER} -p${ADC_DATABASE_PASS} adc -e "UPDATE PLATFORM_AWS SET VPC_ID='${VPC_ID}',VPC=1,AVAILABILITY_ZONE='${AVAILABILITY_ZONE}' WHERE PLATFORM_NO=1;"

#Set zabbix parameters
echo "[ 5/10] Set application parameters for zabbix"
sed -i -e "s/\(\$DB\[\"USER\"\][[:space:]]*=\).*/\1 '$ZABBIX_DATABASE_USER';/" /etc/zabbix/zabbix.conf.php
sed -i -e "s/\(\$DB\[\"PASSWORD\"\][[:space:]]*=\).*/\1 '$ZABBIX_DATABASE_PASS';/" /etc/zabbix/zabbix.conf.php

sed -i -e "s/DBUser=root/DBUser=${ZABBIX_DATABASE_USER}/" /etc/zabbix/zabbix_server.conf
sed -i -e "s/^# DBPassword=/DBPassword=${ZABBIX_DATABASE_PASS}/" /etc/zabbix/zabbix_server.conf

#Set /opt/adc/conf/config/properties
echo "[ 6/10] Set application parameters for pcc-core"

sed -i -e "s/db.username =.*/db.username = $ADC_DATABASE_USER/" /opt/adc/conf/config.properties
sed -i -e "s/db.password =.*/db.password = $ADC_DATABASE_PASS/" /opt/adc/conf/config.properties
sed -i -e "s/db.log.username =.*/db.log.username = $ADC_DATABASE_USER/" /opt/adc/conf/config.properties
sed -i -e "s/db.log.password =.*/db.log.password = $ADC_DATABASE_PASS/" /opt/adc/conf/config.properties
sed -i -e "s/dns.domain =.*/dns.domain = $DOMAIN_NAME/" /opt/adc/conf/config.properties
sed -i -e "s/vpn.server =.*/vpn.server = $PUBLICIP/" /opt/adc/conf/config.properties
sed -i -e "s/vpn.zippass =.*/vpn.zippass = $CLIENT_ZIP_PASS/" /opt/adc/conf/config.properties
sed -i -e "s/vpn.clienturl =.*/vpn.clienturl = https:\/\/$PUBLICIP\/keys\/client.zip/" /opt/adc/conf/config.properties
sed -i -e "s/puppet.masterHost =.*/puppet.masterHost = $HOST_NAME/" /opt/adc/conf/config.properties
sed -i -e "s/zabbix.display =.*/zabbix.display = https:\/\/$PUBLICIP\/zabbix\//" /opt/adc/conf/config.properties

#Set /opt/adc/iaassystem.ini for  iaasgateway
echo "[ 7/10] Set application parameters for iaas-gateway"

sed -i -e "s/USER =.*/USER = $ADC_DATABASE_USER/" /opt/adc/iaasgw/iaassystem.ini
sed -i -e "s/PASS =.*/PASS = $ADC_DATABASE_PASS/" /opt/adc/iaasgw/iaassystem.ini

#Set /opt/adc/management-tool/config/management-config.properties for management tools
echo "[ 8/10] Set application parameters for management tools"
sed -i -e "s/ZABBIX_DB_USER=.*/ZABBIX_DB_USER=$ZABBIX_DATABASE_USER/" /opt/adc/management-tool/config/management-config.properties
sed -i -e "s/ZABBIX_DB_PASSWORD=.*/ZABBIX_DB_PASSWORD=$ZABBIX_DATABASE_PASS/" /opt/adc/management-tool/config/management-config.properties
sed -i -e "s#AWS_ACCESS_ID=.*#AWS_ACCESS_ID=${AWS_ACCESS_ID}#" /opt/adc/management-tool/config/management-config.properties
sed -i -e "s#AWS_SECRET_KEY=.*#AWS_SECRET_KEY=${AWS_SECRET_KEY}#" /opt/adc/management-tool/config/management-config.properties

#Set /etc/pam.d/openvpn and /etc/openvpn/loaduserDB.sh for openvpn
echo "[ 9/10] Set application parameters for openvpn"

sed -i -e "s/user=\w\+/user=$ADC_DATABASE_USER/" /etc/pam.d/openvpn
sed -i -e "s/passwd=\w\+/passwd=$ADC_DATABASE_PASS/" /etc/pam.d/openvpn
sed -i -e "s/USERNAME=\"\w\+\"/USERNAME=\"$ADC_DATABASE_USER\"/" /etc/openvpn/loaduserDB.sh
sed -i -e "s/PASSWORD=\"\w\+\"/PASSWORD=\"$ADC_DATABASE_PASS\"/" /etc/openvpn/loaduserDB.sh

#create credential set  clinet.zip for vpn client
echo "[10/10] Create credential client.zip for openvpn"
if [ ! -f ${BASE_DIR}/createCredential.sh ]; then
  echo "${BASE_DIR}/createCredential.sh: No such file"
  exit 1
fi

sh ${BASE_DIR}/createCredential.sh

if [ $? -ne 0 ]; then
	echo "Error: Create credential client.zip failed"
	exit 1
fi

cd /etc/openvpn/easy-rsa/keys/client
zip -P ${CLIENT_ZIP_PASS} -r client.zip * > /dev/null

#Set clinet.zip for apache
htpasswd -b -c -m /etc/httpd/conf/.htpasswd client ${CLIENT_ZIP_PASS} > /dev/null 2>&1
chmod 644 /etc/httpd/conf/.htpasswd
cp /etc/openvpn/easy-rsa/keys/client/client.zip /opt/adc/keys


cd ${BASE_DIR}


#Set chkconfig
chkconfig named on
chkconfig openvpn on
chkconfig puppetmaster on
chkconfig mysqld on
chkconfig tomcat on
chkconfig httpd on
chkconfig zabbix-agent on
chkconfig zabbix-server on

#start services
echo ""
echo ""
echo "------------------------------------------------"

/etc/init.d/openvpn start
/etc/init.d/named restart
/etc/init.d/puppetmaster start
/etc/init.d/mysqld restart
/etc/init.d/tomcat start
/etc/init.d/httpd start
/etc/init.d/zabbix-agent start
/etc/init.d/zabbix-server start

echo "------------------------------------------------"
echo "Setup is finishded."
echo ""
echo " PCC    Login URL https://${PUBLICIP}/auto-web/"
echo " Zabbix Login URL https://${PUBLICIP}/zabbix/"

echo "Sample username and password are below" 
echo "username/ password : test/test"
echo "------------------------------------------------"

exit 0

