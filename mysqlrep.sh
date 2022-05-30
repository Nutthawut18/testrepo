#!/bin/bash

redcolorfnt='\033[0;31m'
greencolorfnt='\033[0;32m'
NC='\033[0m'

#### Check Server ####
mysqlservice=$(ss -lntp | grep mysql)
mysqldir=$(ls /data01/mysql/data/)
etcmycnf=$(find /etc/ -name my.cnf)
mysqldlog=$(find /var/log/ -name mysqld.log)

if [[ -z $mysqlservice ]]; then
echo -e "${greencolorfnt}mysql service is not running${NC}";
else
echo -e "${redcolorfnt}mysql service is running${NC}";
fi
if [[ -z $mysqldir ]]; then
echo -e "${greencolorfnt}Directory /data01/mysql/data/ is empty${NC}";
else
echo -e "${redcolorfnt}Directory /data01/mysql/data/ is not empty${NC}";
fi
if [[ -z $etcmycnf ]]; then
echo -e "${greencolorfnt}Not found my.cnf in /etc/${NC}";
else
echo -e "${redcolorfnt}Found my.cnf in /etc/${NC}";
fi
if [[ -z $mysqldlog ]]; then
echo -e "${greencolorfnt}Not found mysqld.log in /var/log/${NC}";
else
echo -e "${redcolorfnt}Found mysqld.log in /var/log/${NC}";
fi

if [[ -z $mysqlservice ]] && [[ -z $mysqldir ]] && [[ -z $etcmycnf ]] && [[ -z $mysqldlog ]]; then
while true; do
    read -p "************ Do you want to next step ? (y,n)" checkserver
    case $checkserver in
        [Yy]* ) break;;
        [Nn]* ) echo "Exit..."; exit;;
        * ) echo "Please answer yes or no.";;
    esac
done
else
echo -e "${redcolorfnt}This server isn't ready to install please recheck it.${NC}";
exit 0
fi
#### END Check Server ####

#### Check Type Server ####
PS3='Select type of this server (example answer 1,2,3): '
options=("Primary" "Secondary" "Exit")
select opt in "${options[@]}"
do
    case $opt in
        "Primary") break;;
        "Secondary") read -p "Enter your GroupUUID from your Primary server :" priUUID; break;;
        "Exit") echo "Exit..."; exit;;
        *) echo "invalid option $REPLY";;
    esac
done
#### END Check Type Server ####

#### Config serverid localaddress and seeds ####
read -p "Enter your server_id :" serverid
read -p "Enter your local_address :" localaddress
read -p "How much your seeds :" numseeds

touch ./hostname.txt

for (( i = 1; i <= $numseeds; i++ ))
do
        read -p "Your seeds hostname $i is :" hostnameseeds
        for h in "${hostnameseeds[@]}"
        do
                echo Seeds hostname $i =$h:33061, | tee -a ./hostname.txt &>/dev/null
        done
done
#### END Config serverid localaddress and seeds ####

#### Recheck all value ####
echo -e "${greencolorfnt}******* Please check you value ********${NC}"
echo "Type of this server :"$opt;
if [[ $opt == *"Secondary"* ]]; then
echo -e "Your GroupUUID from your Primary server is :"${greencolorfnt}$priUUID${NC};
fi
echo "Your serverid is :"$serverid;
echo "Your local_address is :"$localaddress;
cat ./hostname.txt | cut -f1 -d","

sdhns=$(grep 'Seeds hostname *' ./hostname.txt | awk -F ' ' '{print $(NF)}' | cut -f2 -d"=" | tr -d '\n' | rev | cut -c 2- | rev)

while true; do
    read -p "Is correct value ? (y,n)" checkvalue
    case $checkvalue in
        [Yy]* ) break;;
        [Nn]* ) echo "Exit..."; exit;;
        * ) echo "Please answer yes or no.";;
    esac
done
#### END Recheck all value ####

#### Install mysql with rpm ####
read -p "Please enter directory your rpm files :" rpmdir

ls -la $rpmdir | grep rpm

while true; do
    read -p "Is correct rpm ? (y,n)" checkrpmdir
    case $checkrpmdir in
        [Yy]* ) rpm -ivh $rpmdir/*.rpm; break;;
        [Nn]* ) echo "Exit..."; exit;;
        * ) echo "Please answer yes or no.";;
    esac
done
#### Install mysql with rpm ####

#### start mysql and set password root null ####
systemctl start mysqld
passmysqlfirstinstall=$(grep 'A temporary password is generated for root@localhost' /var/log/mysqld.log | awk -F ' ' '{print $(NF)}')

mysql -u root -p$passmysqlfirstinstall --connect-expired-password << EOF
ALTER USER 'root'@'localhost' IDENTIFIED BY '!S3cr3t!';
UPDATE mysql.user SET authentication_string=null WHERE User='root';
FLUSH PRIVILEGES;
exit
EOF
#### END start mysql and set password root null ####

#### Create user group replication ####
mysql --connect-expired-password << EOF
SET SQL_LOG_BIN=0;
CREATE USER rpl_user@'%' IDENTIFIED BY 'Repl!passw0rd' REQUIRE SSL;
GRANT REPLICATION SLAVE ON *.* TO rpl_user@'%';
GRANT BACKUP_ADMIN ON *.* TO rpl_user@'%';
FLUSH PRIVILEGES;
SET SQL_LOG_BIN=1;
exit
EOF
#### END Create user group replication ####

#### Create keyring #####
mkdir -p /opt/mysql/mysql-keyring && chown -R mysql:mysql /opt/mysql
systemctl restart mysqld
#### END Create keyring #####

#### Select UUID for group replication ####
selectUUID=$(echo "select UUID()" | mysql)
grepUUID=$(echo $selectUUID | awk {'print $2'})
#### END Select UUID for group replication ####

#### Config /etc/my.cnf ####
mv /etc/my.cnf /etc/my.cnf.bak
touch /etc/my.cnf

echo '[mysqld]

datadir=/data01/mysql/data
socket=/var/lib/mysql/mysql.sock

log-error=/data01/mysql/log/mysqld.log
pid-file=/var/run/mysqld/mysqld.pid

#require_secure_transport=ON
#tls_version=TLSv1.3

early-plugin-load=keyring_file.so
keyring_file_data=/opt/mysql/mysql-keyring/keyring

disabled_storage_engines="MyISAM,BLACKHOLE,FEDERATED,ARCHIVE,MEMORY"

server_id=serverid_cnf
gtid_mode=ON
enforce_gtid_consistency=ON
log_bin=binlog
log_slave_updates=ON
binlog_format=ROW
master_info_repository=TABLE
relay_log_info_repository=TABLE
transaction_write_set_extraction=XXHASH64

plugin_load_add='group_replication.so'
group_replication_group_name="groupUUID"
group_replication_start_on_boot=off
group_replication_local_address= "localaddress:33061"
group_replication_group_seeds= "hostname"
group_replication_bootstrap_group=off

group_replication_recovery_get_public_key = 1
group_replication_ssl_mode=REQUIRED
group_replication_ip_whitelist="119.59.119.0/24"
group_replication_ip_allowlist="119.59.119.0/24"
max_connections=4000
max_error_count=100000' \
> /etc/my.cnf

if [[ $opt == *"Primary"* ]]; then
sed -i -e "s/serverid_cnf/$serverid/" /etc/my.cnf
sed -i -e "s/groupUUID/$grepUUID/" /etc/my.cnf
sed -i -e "s/localaddress/$localaddress/" /etc/my.cnf
sed -i -e "s/hostname/$sdhns/" /etc/my.cnf
elif [[ $opt == *"Secondary"* ]]; then
sed -i -e "s/serverid_cnf/$serverid/" /etc/my.cnf
sed -i -e "s/groupUUID/$priUUID/" /etc/my.cnf
sed -i -e "s/localaddress/$localaddress/" /etc/my.cnf
sed -i -e "s/hostname/$sdhns/" /etc/my.cnf
fi

systemctl restart mysqld
#### END Config /etc/my.cnf ####

#### CHANGE DATADIR ####
systemctl stop mysqld
sleep 1m
mkdir -p /data01/mysql/data
mkdir -p /data01/mysql/log
chown -Rf mysql:mysql /data01/mysql/data
chown -Rf mysql:mysql /data01/mysql/log
rsync -va --progress /var/lib/mysql/ /data01/mysql/data/
systemctl start mysqld
sleep 1m
#### END CHANGE DATADIR ####

#### start primary group replication and echo group replication UUID ####
if [[ $opt == *"Primary"* ]]; then
mysql --connect-expired-password << EOF
SET GLOBAL group_replication_bootstrap_group=ON;
START GROUP_REPLICATION;
SET GLOBAL group_replication_bootstrap_group=OFF;
exit
EOF
echo "******************************************************************";
echo "This is GroupUUID please keep this to install secondary server";
echo -e ${greencolorfnt}$grepUUID${NC};
echo "******************************************************************";
echo "If you lost it. You can find it in /etc/my.cnf in line group_replication_group_name"
#### END start primary group replication and echo group replication UUID ####

#### Secondary node join group replication ####
elif [[ $opt == *"Secondary"* ]]; then
mysql --connect-expired-password << EOF
SET GLOBAL group_replication_recovery_use_ssl=1;
CHANGE REPLICATION SOURCE TO SOURCE_USER='rpl_user', SOURCE_PASSWORD='Repl!passw0rd' FOR CHANNEL 'group_replication_recovery';
START GROUP_REPLICATION;
exit
EOF
fi
#### END Secondary node join group replication ####
rm -rf ./hostname.txt