#!/bin/bash

#TODO make sure all user provided variables are escaped for bash, sed, and irssi config to not break on special characters

if [[ ! `which bash` ]] ; then
	echo "this shell script requires bash"
	exit 1
fi

if [[ `id -u` -ne 0 ]] ; then
	echo "please run with sudo"
	exit 1
fi

dionysus_path=$PWD

# get quick dionysus settings from file if it exists
if [ -f "./dionysus.settings" ] ; then
	. ./dionysus.settings
fi

echo ""
echo "dionysus system setup - irc segment"
echo "tested with debian-10.0.0-amd64-i386-netinst.iso"
echo "this will install:"
echo " - an irc server (unrealircd)"
echo " - services for that server (anope)"
echo " - a helper bot (using irssi and autorun scripts)"
echo " - an irc bouncer (znc)"
echo " - a discord-irc bridge (dis4irc)"
echo ""
echo " user provided variables aren't currently escaped for bash, sed, or irssi config"
echo " be aware when using special characters"
echo "press enter to continue"
read

echo "install wget, screen"
apt-get install -y wget screen

# get user variables
while [ -z "$irc_network_hostname" ] ; do
	echo "enter the irc network hostname (e.g. localhost.net)"
	read irc_network_hostname
done
while [ -z "$irc_services_hostname" ] ; do
	echo "enter the irc services hostname (e.g. services.localhost.net)"
	read irc_services_hostname
done
while [ -z "$irc_stats_hostname" ] ; do
	echo "enter the irc stats hostname (e.g. stats.localhost.net)"
	read irc_stats_hostname
done
while [ -z "$irc_server_uplink_pass" ] ; do
	echo "enter the irc server uplink pass"
	read irc_server_uplink_pass
done
while [ -z "$irc_network_name" ] ; do
	echo "enter the irc network name (e.g. LocalNet)"
	read irc_network_name
done
while [ -z "$irc_sendfrom_mail" ] ; do
	echo "enter the address irc should send mail from (e.g. irc@localhost.net)"
	read irc_sendfrom_mail
done
while [ -z "$irc_server_hostname" ] ; do
	echo "enter the irc server's hostname (e.g. irc.foonet.com)"
	read irc_server_hostname
done
while [ -z "$irc_server_info" ] ; do
	echo "enter the irc server's additional info string (e.g. FooNet Server)"
	read irc_server_info
done
while [ -z "$irc_server_admin_name" ] ; do
	echo "enter the irc server's admin name (e.g. admin)"
	read irc_server_admin_name
done
while [ -z "$irc_server_admin_nick" ] ; do
	echo "enter the irc server's admin nick (e.g. admin)"
	read irc_server_admin_nick
done
while [ -z "$irc_server_admin_mail" ] ; do
	echo "enter the irc server's admin mail (e.g. admin@localhost.net)"
	read irc_server_admin_mail
done
while [ -z "$kline_address" ] ; do
	echo "enter the kline address (e.g. kline@localhost.net)"
	read kline_address
done

# supplemental users

# install build-essential and irssi
apt-get install -y build-essential irssi

################################################################################
################################################################################
################################################################################
################################################################################

# install anope
useradd -m irc_services
mkdir -p /home/irc_services/.anope/conf

if [ $anope_from_source -eq 1 ] ; then
	mkdir /home/irc_services/opt
	# install anope from source
	# https://wiki.anope.org/index.php/2.0/Installation

	# install cmake
	sudo apt-get install -y cmake

	# get latest anope from https://github.com/anope/anope/releases/latest 
	cd /tmp
	wget https://github.com/anope/anope/releases/download/2.0.6/anope-2.0.6-source.tar.gz
	tar xvfz anope-2.0.6-source.tar.gz
	cd anope-2.0.6-source

	# configure for installing to /home/irc_services/opt/anope
	{ echo "/home/irc_services/opt/anope";
		echo "y"; # create directory
		echo ""; # don't force files to be owned by a particular group
		echo ""; # default file permissions
		echo ""; # no debug
		echo ""; # no precompiled headers
		echo ""; # no extra include directories
		echo ""; # no extra library directories
		echo ""; # no extra arguments to cmake
	} | ./Config
	cd build
	make
	make install
	make clean

	# copy configs to irc_services user
	cp /home/irc_services/opt/anope/conf/* /home/irc_services/.anope/conf
	mv /home/irc_services/opt/anope/conf/example.conf /home/irc_services/opt/anope/conf/services.conf

	# anope binary
	anope_services_binary=$anope_install_dir/bin/services
	anope_start_options=""

	#TODO enable anope to run at system start
else
	# install anope from package
	apt-get install -y anope

	# copy configs to irc_services user
	cp /etc/anope/* /home/irc_services/.anope/conf

	# ensure irc_services can write to pid file
	mkdir /var/run/anope
	chown irc_services:irc_services /var/run/anope

	# anope binary
	anope_services_binary=/usr/sbin/anope
	anope_start_options="--localedir=/usr/share/anope --modulesdir=/usr/lib/anope"

	# ensure irc_services user can run anope
	chown irc_services:irc_services $anope_services_binary

	#TODO enable anope to run at system start
fi

# create data and log dirs
mkdir /home/irc_services/.anope/data
mkdir /home/irc_services/.anope/logs

# anope config file
anope_conf=/home/irc_services/.anope/conf/services.conf

# edit anope config
sed -i "s/value = \"services.localhost.net\"/value = \"$irc_services_hostname\"/" $anope_conf
sed -i "s/name = \"services.localhost.net\"/name = \"$irc_services_hostname\"/" $anope_conf
sed -i "s/port = 7000/port = 6667/" $anope_conf
sed -i "s/password = \"mypassword\"/password = \"$irc_server_uplink_pass\"/" $anope_conf
sed -i "s/name = \"inspircd20\"/name = \"unreal4\"/" $anope_conf
sed -i "s/networkname = \"LocalNet\"/networkname = \"$irc_network_name\"/" $anope_conf
sed -i -E "s/#seed = (.+)/seed = \1/" $anope_conf
sed -i "s/usemail = yes/usemail = no/" $anope_conf

# edit operserv config
sed -i "s/defaultsessionlimit = 3/defaultsessionlimit = 32/" /home/irc_services/.anope/conf/operserv.conf

# ensure irc_services user can access all anope files
chown irc_services:irc_services /home/irc_services/.anope
chown -R irc_services:irc_services /home/irc_services/.anope/*

# create script to start anope as irc_services
echo "#!/bin/bash
sudo -u irc_services $anope_services_binary --confdir=/home/irc_services/.anope/conf --dbdir=/home/irc_services/.anope/data --logdir=/home/irc_services/.anope/logs $anope_start_options">/home/irc_services/start_anope.sh
chmod +x /home/irc_services/start_anope.sh

################################################################################
################################################################################
################################################################################
################################################################################

# install unrealircd
# https://www.unrealircd.org/docs/Installing_from_source
useradd -m ircd
mkdir /home/ircd/opt

# get latest unrealircd from https://www.unrealircd.org/download 4.2.4.1)
cd /tmp
wget https://www.unrealircd.org/unrealircd4/unrealircd-4.2.4.1.tar.gz
tar xvfz unrealircd-4.2.4.1.tar.gz
cd unrealircd-4.2.4.1

# configure for installing to /usr/local/opt/unrealircd
apt-get install -y openssl libssl-dev 

unreal_install_dir=/home/ircd/opt/unrealircd

echo "#
BASEPATH=\"$unreal_install_dir\"
BINDIR=\"$unreal_install_dir/bin\"
DATADIR=\"$unreal_install_dir/data\"
CONFDIR=\"$unreal_install_dir/conf\"
MODULESDIR=\"$unreal_install_dir/modules\"
LOGDIR=\"$unreal_install_dir/logs\"
CACHEDIR=\"$unreal_install_dir/cache\"
DOCDIR=\"$unreal_install_dir/doc\"
TMPDIR=\"$unreal_install_dir/tmp\"
LIBDIR=\"$unreal_install_dir/lib\"
PREFIXAQ=\"1\"
MAXSENDQLENGTH=\"3000000\"
MAXCONNECTIONS_REQUEST=\"auto\"
NICKNAMEHISTORYLENGTH=\"2000\"
DEFPERM=\"0600\"
SSLDIR=\"\"
REMOTEINC=\"\"
CURLDIR=\"\"
SHOWLISTMODES=\"1\"
TOPICNICKISNUH=\"\"
SHUNNOTICES=\"\"
NOOPEROVERRIDE=\"\"
DISABLEUSERMOD=\"\"
OPEROVERRIDEVERIFY=\"\"
DISABLEEXTBANSTACKING=\"\"
GENCERTIFICATE=\"0\"
EXTRAPARA=\"\"
ADVANCED=\"\"">/tmp/unrealircd-4.2.4.1/config.settings
./Config -quick
make
make install
make clean

# create irc server 10 year cert
# auto cert generation
echo "generating cert for unrealircd"
/usr/bin/openssl req -newkey rsa:2048 -new -nodes -x509 -days 3650 -sha256 -keyout /tmp/key.pem -out /tmp/cert.pem -subj "/C=AQ/ST=Ross Dependency/L=/O=/OU=/CN="

echo "removing read write and execute permissions from unrealircd key and cert"
chmod o-rwx /tmp/key.pem /tmp/cert.pem
chmod g-rwx /tmp/key.pem /tmp/cert.pem

echo "moving key and cert to unrealircd conf ssl"
mv /tmp/key.pem $unreal_install_dir/conf/ssl/server.key.pem
mv /tmp/cert.pem $unreal_install_dir/conf/ssl/server.cert.pem

# unrealircd config file
unrealircd_conf=$unreal_install_dir/conf/unrealircd.conf

# copy example config
echo "copying unrealircd example config"
cp $unreal_install_dir/conf/examples/example.conf $unrealircd_conf

# motd
if [ -f $dionysus_path/ircd.motd ] ; then
	echo "copying motd"
	cp $dionysus_path/ircd.motd $unreal_install_dir/conf/ircd.motd
fi

# ensure ircd user can access all unrealircd files
echo "chowning unrealircd install dir to ircd user"
chown ircd:ircd $unreal_install_dir
chown -R ircd:ircd $unreal_install_dir/*

# generate cloak keys to use later (as ircd user)
echo "generating unrealircd cloak keys"
mapfile -t cloak_keys < <(( sudo -u ircd $unreal_install_dir/unrealircd gencloak ) 2>&1)

# edit config
# me block
echo "me block"
sed -i "s/name \"irc.foonet.com\";/name \"$irc_server_hostname\";/" $unrealircd_conf
sed -i "s/info \"FooNet Server\";/info \"$irc_server_info\";/" $unrealircd_conf

# admin block
echo "admin block"
sed -i "s/\"Bob Smith\";/\"$irc_server_admin_name\";/" $unrealircd_conf
sed -i "s/\"bob\";/\"$irc_server_admin_nick\";/" $unrealircd_conf
sed -i "s/\"widely@used.name\";/\"$irc_server_admin_mail\";/" $unrealircd_conf

# add client class for local bouncer with high maxperip
echo "allow 127.0.0.1 block"
echo "allow {
	ip *@127.0.0.1;
	class clients;
	maxperip 32;
}
">>$unrealircd_conf

echo "comment password"
sed -i "s/password \"test\";/#password \"test\";/" $unrealircd_conf # this will also replace the password line in the example oper and vhost blocks

while [ -z "$admin_oper_name" ] ; do
	echo "enter admin oper's name"
	read admin_oper_name
done
while [ -z "$admin_oper_whois" ] ; do
	echo "enter admin oper's whois"
	read admin_oper_whois
done
while [ -z "$admin_oper_vhost" ] ; do
	echo "enter admin oper's vhost"
	read admin_oper_vhost
done
while [ -z "$admin_oper_password" ] ; do
	echo "enter admin oper's pass"
	read admin_oper_pass
done

echo "admin oper"
sed -i "s/oper bobsmith {/oper $admin_oper_name {/" $unrealircd_conf
sed -i "s/swhois \"is a Network Administrator\";/swhois \"$admin_oper_whois\";/" $unrealircd_conf
sed -i "s/vhost netadmin.mynet.org;/vhost $admin_oper_vhost;password \"$admin_oper_password\";/" $unrealircd_conf

#TODO services listen block? with ip *;, port 7000;, and options { serversonly; };
#TODO remove example hub link block?

# services link block
echo "services link block"
sed -i "s/link services.mynet.org/link $irc_services_hostname/" $unrealircd_conf
sed -i "s/password \"changemeplease\";/password \"$irc_server_uplink_pass\";/" $unrealircd_conf

# ulines block
echo "services ulines block"
sed -i "s/services.mynet.org;/$irc_services_hostname;/" $unrealircd_conf

# except ban and tkl
echo "except ban and tk1 for 127.0.0.1"
sed -i "s/mask \*@192.0.2.1;/mask \*@127.0.0.1;/" $unrealircd_conf

# except throttle
echo "except throttle for 127.0.0.1"
echo "except throttle {
	mask 127.0.0.1;
};
">>$unrealircd_conf

# deny channel block to prevent channel creation
echo "deny channel block"
sed -i "s/channel \"\*warez\*\";/channel \"\*\";/" $unrealircd_conf
sed -i "s/reason \"Warez is illegal\";/reason \"Creating channels is prohibited\";/" $unrealircd_conf

# create persistent channels
echo "create default channel blocks"
echo "allow channel {
	channel \"#help\";
};
allow channel {
	channel \"#general\";
};
">>$unrealircd_conf

if [ $predefined_channels -eq 1 ] ; then
	echo "adding additional channels"
	another="y"
	channel_index=0
else
	if [ $predefined_channels -eq 0 ] ; then
		echo "skipping additional channels"
		another="n"
	else
		read -p "add persistent channels besides #help and #general? [y/N] " another
	fi
fi

if [ "$another" = "Y" ] || [ "$another" = "y" ] ; then
	add_channel=1
else
	add_channel=0
fi

while [ $add_channel -eq 1 ] ; do
	if [ $predefined_channels -eq 1 ] ; then
		# get next predefined channel
		channel="${channel_names[channel_index]}"
		(( channel_index++ ))
		if [ ${#channel_names[@]} -eq $channel_index ] ; then
			add_channel=0
		else
			add_channel=1
		fi
	else
		echo "enter channel (without leading #)"
		read channel
		read -p "add another channel? [y/N] " another
		if [ "$another" = "Y" ] || [ "$another" = "y" ] ; then
			add_channel=1
		else
			add_channel=0
		fi
	fi

	# add to unrealirc
	echo "allow channel {
	channel \"#$channel\";
};
">>$unrealircd_conf
done

# restrict the example vhost block
echo "restrict example vhost block"
sed -i "s/mask \*@unrealircd.com;/mask \*@localhost;password \"test\";/" $unrealircd_conf

# network configuration set block
echo "network configuration set block"
sed -i "s/\"MYNet\";/\"$irc_network_name\";/" $unrealircd_conf
sed -i "s/\"irc.mynet.org\";/\"$irc_network_hostname\";/" $unrealircd_conf
sed -i "s/\"services.mynet.org\";/\"$irc_services_hostname\";/" $unrealircd_conf
sed -i "s/\"Help\";/\"#help\";/" $unrealircd_conf
sed -i "s/\"aoAr1HnR6gl3sJ7hVz4Zb7x4YwpW\";/\"${cloak_keys[1]}\";\"${cloak_keys[2]}\";\"${cloak_keys[3]}\";/" $unrealircd_conf
sed -i "s/\"and another one\";//" $unrealircd_conf

# server specific configuration set block
echo "server specific configuration set block"
sed -i "s/kline-address \"set.this.to.email.address\";/kline-address \"$kline_address\";/" $unrealircd_conf

# add blocks for additional opers
if [ $predefined_opers -eq 1 ] ; then
	echo "adding additional opers"
	another="y"
	oper_index=0
else
	if [ $predefined_opers -eq 0 ] ; then
		echo "skipping additional opers"
		another="n"
	else
		read -p "add another oper? [y/N] " another
	fi
fi

if [ "$another" = "Y" ] || [ "$another" = "y" ] ; then
	add_oper=1
else
	add_oper=0
fi

while [ $add_oper -eq 1 ] ; do
	if [ $predefined_opers -eq 1 ] ; then
		# get next predefined opers
		oper_name="${oper_names[oper_index]}"
		oper_pass="${oper_passwords[oper_index]}"
		oper_whois="${oper_whoises[oper_index]}"
		oper_vhost="${oper_vhosts[oper_index]}"
		(( oper_index++ ))
		if [ ${#oper_names[@]} -eq $oper_index ] ; then
			add_oper=0
		else
			add_oper=1
		fi
	else
		echo "enter oper's name"
		read oper_name
		echo "enter oper's whois"
		read oper_whois
		echo "enter oper's vhost"
		read oper_vhost
		echo "enter oper's pass"
		read oper_pass
		read -p "add another oper? [y/N] " another
		if [ "$another" = "Y" ] || [ "$another" = "y" ] ; then
			add_oper=1
		else
			add_oper=0
		fi
	fi

	# add to anope
	echo "oper
{
	name = \"$oper_name\"
	type = \"Services Root\"
}
">>$anope_conf

	# add to unrealirc
	echo "oper $oper_name {
	class opers;
	mask *@*;
	password \"$oper_pass\";
	operclass netadmin;
	swhois \"$oper_whois\";
	vhost $oper_vhost;
};">>$unrealircd_conf
done

# create script to start unrealircd as ircd
echo "creating unrealircd start script"
echo "#!/bin/bash
sudo -u ircd $unreal_install_dir/bin/unrealircd">/home/ircd/start_unrealircd.sh
chmod +x /home/ircd/start_unrealircd.sh

################################################################################
################################################################################
################################################################################
################################################################################

# start unrealircd and anope
echo "starting unrealircd and anope"
/home/ircd/start_unrealircd.sh
/home/irc_services/start_anope.sh

################################################################################
################################################################################
################################################################################
################################################################################

# set up irc helper
echo "setting up irc helper"
useradd -m irc_helper

while [ -z "$irc_helper_nick" ] ; do
	echo "enter the irc helper's nick (e.g. helper)"
	read irc_helper_nick
done
while [ -z "$irc_helper_nick_pass" ] ; do
	echo "enter the irc helper's nick pass"
	read irc_helper_nick_pass
done
while [ -z "$irc_helper_mail" ] ; do
	echo "enter the irc helper's mail (e.g. helper@localhost.net)"
	read irc_helper_mail
done
while [ -z "$irc_helper_vhost" ] ; do
	echo "enter the irc helper's vhost"
	read irc_helper_vhost
done

if [ $irc_helper_oper -eq 1 ] ; then
	echo "irc helper will be oper"
	helper_oper="y"
else
	if [ $irc_helper_opers -eq 0 ] ; then
		echo "irc helper will not be oper"
		helper_oper="n"
	else
		read -p "cause irc helper to authenticate as oper? [y/N] " another
	fi
fi

irc_helper_oper_config=""
if [ "$helper_oper" = "Y" ] || [ "$helper_oper" = "y" ] ; then
	while [ -z "$irc_helper_oper_name" ] ; do
		echo "enter the irc helper's oper name"
		read irc_helper_oper_name
	done
	while [ -z "$irc_helper_oper_pass" ] ; do
		echo "enter the irc helper's oper pass"
		read irc_helper_oper_pass
	done
	irc_helper_oper_config="; \/oper ${irc_helper_oper_name} ${irc_helper_oper_pass}"
fi

mkdir /home/irc_helper/.irssi
mkdir -p /home/irc_helper/.irssi/scripts/autorun
chown irc_helper:irc_helper /home/irc_helper/.irssi
chown -R irc_helper:irc_helper /home/irc_helper/.irssi/*

# install json and list/moreutils for perl
apt-get install -y libjson-perl liblist-moreutils-perl

# generate default network config for local
echo "/server add -auto -network local localhost
/network add -nick $irc_helper_nick -autosendcmd '/quit' local
/channel add -auto #general local
">/home/irc_helper/.irssi/startup
sudo -u irc_helper irssi

# clear irc_helper irssi startup
rm /home/irc_helper/.irssi/startup

# replace autosendcmd for local network in config with nick registration, identification, vhost request, vhost on, and quit
sed -i "s/autosendcmd = \"\/quit\";/autosendcmd = \"\/msg nickserv register ${irc_helper_nick_pass} ${irc_helper_mail}; wait 2000; \/msg nickserv identify ${irc_helper_nick_pass}; wait 2000; \/msg hostserv request ${irc_helper_vhost}; wait 2000; \/msg hostserv on; \/quit\";/" /home/irc_helper/.irssi/config
sudo -u irc_helper irssi

# replace autosendcmd for local network in config with just identify (and oper if specified)
sed -i "s/autosendcmd = \"\/msg nickserv register ${irc_helper_nick_pass} ${irc_helper_mail}; wait 2000; \/msg nickserv identify ${irc_helper_nick_pass}; wait 2000; \/msg hostserv request ${irc_helper_vhost}; wait 2000; \/msg hostserv on; \/quit\";/autosendcmd = \"\/msg nickserv identify ${irc_helper_nick_pass}${irc_helper_oper_config}\";/" /home/irc_helper/.irssi/config

# add helper scripts to irssi autorun
if [ -d "$dionysus_path/irc_helper_scripts" ] ; then
	cp $dionysus_path/irc_helper_scripts/* /home/irc_helper/.irssi/scripts/autorun
	chown irc_helper:irc_helper /home/irc_helper/.irssi/scripts/autorun
	chown -R irc_helper:irc_helper /home/irc_helper/.irssi/scripts/autorun/*
fi

# set up irc helper start script
echo "#!/bin/bash
sudo -u irc_helper screen -d -m irssi
echo \"launching irc helper into background\"
">/home/irc_helper/start_irc_helper.sh
chmod +x /home/irc_helper/start_irc_helper.sh

# start irc helper
/home/irc_helper/start_irc_helper.sh

#TODO enable helper to run at system start

################################################################################
################################################################################
################################################################################
################################################################################

# install znc
apt-get install -y znc

useradd -m znc

mkdir /home/znc/.znc

# get user variables
while [ -z "$znc_port" ] ; do
	echo "enter the znc server port (e.g. 6698)"
	read znc_port
done
while [ -z "$znc_admin_name" ] ; do
	echo "enter the znc admin username (e.g. admin)"
	read znc_admin_name
done
while [ -z "$znc_admin_pass" ] ; do
	echo "enter the znc admin pass"
	read znc_admin_pass
done

# auto cert generation
echo "generating cert for znc"
/usr/bin/openssl req -newkey rsa:2048 -new -nodes -x509 -days 3650 -sha256 -keyout /tmp/key.pem -out /tmp/cert.pem -subj "/C=AQ/ST=Ross Dependency/L=/O=/OU=/CN="

touch /home/znc/.znc/znc.pem
cat /tmp/key.pem > /home/znc/.znc/znc.pem
cat /tmp/cert.pem >> /home/znc/.znc/znc.pem
rm /tmp/key.pem
rm /tmp/cert.pem

chmod o-rwx /home/znc/.znc/znc.pem
chmod g-rwx /home/znc/.znc/znc.pem

# generate znc config
mkdir /home/znc/.znc/configs

mapfile -t znc_pass_block < <(( { echo "$znc_admin_pass"; echo "$znc_admin_pass"; } | sudo -u znc znc --makepass ) 2>&1)

touch /home/znc/.znc/configs/znc.conf
echo "Version = 1.7.2
<Listener l>
        Port = $znc_port
        IPv4 = true
        IPv6 = false
        SSL = true
</Listener>
LoadModule = webadmin

<User $znc_admin_name>
        ${znc_pass_block[5]}
        ${znc_pass_block[6]}
        ${znc_pass_block[7]}
        ${znc_pass_block[8]}
        ${znc_pass_block[9]}
        Admin      = true
        Nick       = $znc_admin_name
        AltNick    = ${znc_admin_name}_
        Ident      = $znc_admin_name
        LoadModule = chansaver
        LoadModule = controlpanel

        <Network $irc_network_name>
                LoadModule = simple_away
                Server     = localhost 6667
        </Network>
</User>
">/home/znc/.znc/configs/znc.conf

# make znc users
if [ $predefined_znc_users -eq 1 ] ; then
	another="y"
	znc_user_index=0
else
	if [ $predefined_znc_users -eq 0 ] ; then
		another="n"
	else
		read -p "add another znc user? [y/N] " another
	fi
fi

if [ "$another" = "Y" ] || [ "$another" = "y" ] ; then
	add_znc_user=1
else
	add_znc_user=0
fi

while [ $add_znc_user -eq 1 ] ; do
	if [ $predefined_znc_users -eq 1 ] ; then
		# get next predefined znc user
		znc_user_name="${znc_user_names[index]}"
		znc_user_pass="${znc_user_passwords[index]}"
		(( znc_user_index++ ))
		if [ ${#znc_user_names[@]} -eq $znc_user_index ] ; then
			add_znc_user=0
		else
			add_znc_user=1
		fi
	else
		echo "enter znc user's name"
		read znc_user_name
		echo "enter znc user's pass"
		read znc_user_pass

		read -p "add another znc user? [y/N] " another
		if [ "$another" = "Y" ] || [ "$another" = "y" ] ; then
			add_znc_user=1
		else
			add_znc_user=0
		fi
	fi

	mapfile -t znc_pass_block < <(( { echo "$znc_user_pass"; echo "$znc_user_pass"; } | sudo -u znc znc --makepass ) 2>&1)

	echo "<User $znc_user_name>
        ${znc_pass_block[5]}
        ${znc_pass_block[6]}
        ${znc_pass_block[7]}
        ${znc_pass_block[8]}
        ${znc_pass_block[9]}
        Admin      = true
        Nick       = $znc_user_name
        AltNick    = ${znc_user_name}_
        Ident      = $znc_user_name
        LoadModule = chansaver
        LoadModule = controlpanel

        <Network $irc_network_name>
                LoadModule = simple_away
                Server     = localhost 6667
        </Network>
</User>
">>/home/znc/.znc/configs/znc.conf
done

# ensure znc user can access all znc files
chown znc:znc /home/znc/.znc
chown -R znc:znc /home/znc/.znc/*

# start znc
sudo -u znc znc

#TODO enable znc to run at system start

################################################################################
################################################################################
################################################################################
################################################################################

# install discord bridge
if [ $install_discord_bridge -eq 1 ] ; then
	bridge="y"
else
	if [ $install_discord_bridge -eq 0 ] ; then
		bridge="n"
	else
		read -p "add discord-irc bridge? [Y/n] " bridge
	fi
fi

if [ "$bridge" = "Y" ] || [ "$bridge" = "y" ] ; then
	useradd -m discord_irc_bridge
	mkdir /home/discord_irc_bridge/opt
	mkdir /home/discord_irc_bridge/opt/dis4irc

	while [ -z "$discord_bridge_bot_nick" ] ; do
		echo "enter the discord bridge bot's nick"
		read discord_bridge_bot_nick
	done
	while [ -z "$discord_bridge_bot_nick_pass" ] ; do
		echo "enter the discord bridge bot's nick pass"
		read discord_bridge_bot_nick_pass
	done
	while [ -z "$discord_bridge_bot_mail" ] ; do
		echo "enter the discord bridge bot's mail"
		read discord_bridge_bot_mail
	done
	while [ -z "$discord_bridge_bot_token" ] ; do
		echo "enter the discord bridge bot's api token"
		read discord_bridge_bot_token
	done
	while [ -z "$discord_channel_id" ] ; do
		echo "enter the discord channel id"
		read discord_channel_id
	done
	while [ -z "$discord_webhook_url" ] ; do
		echo "enter the discord webhook url"
		read discord_webhook_url
	done
	while [ -z "$discord_irc_channel" ] ; do
		echo "enter the name of the channel to bridge to discord (without leading #)"
		read discord_irc_channel
	done

	mkdir /home/discord_irc_bridge/.irssi
	touch /home/discord_irc_bridge/.irssi/startup
	chown discord_irc_bridge:discord_irc_bridge /home/discord_irc_bridge/.irssi
	chown -R discord_irc_bridge:discord_irc_bridge /home/discord_irc_bridge/.irssi/*

	# add discord bridge channel
	echo "allow channel {
	channel \"#${discord_irc_channel}\";
};
">>$unrealircd_conf

	# generate default network config for local
	echo "/server add -auto -network local localhost
/channel add -auto #${disocrd_irc_channel} local
/network add -nick $discord_irc_bridge_nick -autosendcmd '/quit' local
">/home/discord_irc_bridge/.irssi/startup
	sudo -u discord_irc_bridge irssi

	# clear discord_irc_bridge irssi startup"
	rm /home/discord_irc_bridge/.irssi/startup

	# replace autosendcmd for local network in config with nick registration, identification, vhost request, vhost on, and quit
	sed -i "s/autosendcmd = \"\/quit\";/autosendcmd = \"\/msg nickserv register ${discord_bridge_bot_nick_pass} ${discord_bridge_bot_mail}; wait 2000; \/msg nickserv identify ${discord_bridge_bot_nick_pass}; wait 2000; \/msg hostserv request ${discord_bridge_bot_vhost}; wait 2000; \/msg hostserv on; \/quit\";/" /home/discord_irc_bridge/.irssi/config

	sudo -u discord_irc_bridge irssi

	# install java runtime
	apt-get install -y default-jre

	# download latest Dis4IRC from https://github.com/zachbr/Dis4IRC/releases
	cd /home/discord_irc_bridge/opt/dis4irc
	wget https://github.com/zachbr/Dis4IRC/releases/download/v1.0.2/Dis4IRC-1.0.2.jar

	# generate initial config
	java -jar ./Dis4IRC-1.0.2.jar

	# replace the contents of the config
	echo "# Dis4IRC Configuration File

# A list of bridges that Dis4IRC should start up
# Each bridge can bridge multiple channels between a single IRC and Discord Server
bridges {
	default {
		announce-joins-and-quits=false
		announce-extras=false
		channel-mappings {
			\"$discord_channel_id\"=\"#${discord_irc_channel}\"
		}
		discord-api-key=\"$discord_bridge_bot_token\"
		discord-webhooks {
			\"$discord_channel_id\"=\"$discord_webhook_url\"
		}
		irc {
			anti-ping=true
			nickname=$discord_bridge_bot_nick
			no-prefix-regex=\"^\\\\.[A-Za-z0-9]\"
			init-commands-list=[
				\"privmsg nickserv identify $discord_bridge_bot_nick_pass\"
			]
			port=\"6667\"
			realname=BridgeBot
			server=\"localhost\"
			use-ssl=false
			username=$discord_bridge_bot_nick
		}
		mutators {
			paste-service {
				max-message-length=450
				max-new-lines=4
			}
		}
	}
}
debug-logging=true
">/home/discord_irc_bridge/opt/dis4irc/config.hocon

	# ensure discord_irc_bridge user can access all dis4irc files
	chown discord_irc_bridge:discord_irc_bridge /home/discord_irc_bridge/opt/dis4irc
	chown discord_irc_bridge:discord_irc_bridge -R /home/discord_irc_bridge/opt/dis4irc/*

	# set up discord irc bridge start script
	echo "#!/bin/bash
sudo -u discord_irc_bridge screen -d -m java -jar /home/discord_irc_bridge/opt/dis4irc/Dis4IRC-1.0.2.jar
echo \"launching discord irc bridge into background\"
">/home/discord_irc_bridge/start_bridge.sh
	chmod +x /home/discord_irc_bridge/start_bridge.sh

	# start discord irc bridge
	sudo /home/discord_irc_bridge/start_bridge.sh

	# invite the bot to your servers # maybe isn't needed when using webhooks?
	echo "remember to invite the discord bridge bot to your servers by visiting https://discordapp.com/oauth2/authorize?scope=bot&client_id=YOUR_CLIENT_ID"

	#TODO enable discord irc bridge to run at system start
fi

exit 0
