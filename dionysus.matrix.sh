#!/bin/bash

#TODO make sure all user provided variables are escaped for bash, sed, synapse config, and dimension config to not break on special characters

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
echo "dionysus system setup - matrix segment"
echo "tested with"
echo " - debian-10.0.0-amd64-i386-netinst.iso"
echo " - 2019-09-26-raspbian-buster-lite.img"
echo "this will install:"
echo " - a matrix server (synapse)"
echo " - an integrations server (dimension)"
echo " - a matrix web client (riot)"
echo " - a web server to reverse proxy to the matrix server, integrations server, and web client (apache2)"
#TODO echo " - an irc bridge for the integrations server (matrix-org/matrix-appservice-irc)"
#TODO echo " - a discord bridge for the integrations server (Half-Shot/matrix-appservice-discord)"
#TODO echo " - a TURN server for VoIP (coturn)"
echo ""
echo " user provided variables aren't currently escaped for bash, sed, synapse config, or dimension config"
echo " be aware when using special characters"
echo "press enter to continue"
read

#TODO increase size of swapfile on raspberry pi
#/etc/dphys-swapfile
#CONF_SWAPSIZE=100
#CONF_SWAPSIZE=1024
#sudo /etc/init.d/dphys-swapfile restart

################################################################################
################################################################################
################################################################################
################################################################################

echo "install apache"
apt-get install -y apache2
a2enmod proxy proxy_http headers deflate

while [ -z "$le_registration_mail" ] ; do
	echo "enter the mail to use for let's encrypt registrations (e.g. admin@localhost.net)"
	read le_registration_mail
done

################################################################################
################################################################################
################################################################################
################################################################################

echo "install synapse"
DEBIAN_FRONTEND=noninteractive apt-get install -y matrix-synapse

# get synapse variables
while [ -z "$synapse_server_hostname" ] ; do
	echo "enter the synapse server hostname (e.g. synapse.localhost.net)"
	read synapse_server_hostname
done
while [ -z "$matrix_server_hostname" ] ; do
	echo "enter the public matrix server hostname (if different than the synapse server hostname, e.g. localhost.net)"
	read matrix_server_hostname
done
while [ -z "$synapse_server_port" ] ; do
	echo "enter the synapse server port (e.g. 443)"
	read synapse_server_port
done

# replace dots in synapse server hostname for install dir
synapse_server_hostname_underscores="${synapse_server_hostname//./_}"
synapse_install_dir="/etc/matrix-synapse/${synapse_server_hostname_underscores}"
mkdir $synapse_install_dir
mkdir $synapse_install_dir/uploads
mkdir $synapse_install_dir/media_store

synapse_conf=$synapse_install_dir/homeserver.yaml

echo "generating config"
/usr/bin/python3 -B -m synapse.app.homeserver -c "${synapse_conf}" --generate-config --server-name=$matrix_server_hostname --report-stats=no

echo "configure synapse"

# pid
sed -i "s/pid_file:/pid_file: \/etc\/matrix\-synapse\/${synapse_server_hostname_underscores}\/homeserver\.pid\n\#pid_file\:/" $synapse_conf

# disable presence
if [ $synapse_disable_user_presence -eq 1 ] ; then
	echo "disabling user presence"
	disable_presence="y"
else
	if [ $synapse_disable_user_presence -eq 0 ] ; then
		echo "leaving user presence enabled"
		disable_presence="n"
	else
		read -p "disable user presence? [y/N] " disable_presence
	fi
fi

if [ "$disable_presence" = "Y" ] || [ "$disable_presence" == "y" ] ; then
	sed -i "s/use_presence: true/use_presence: false/" $synapse_conf
fi

# whitelist servers
if [ $predefined_synapse_whitelist -eq 1 ] ; then
	echo "adding whitelisted servers"
	another="y"
	whitelist_index=0
else
	if [ $predefined_synapse_whitelist -eq 0 ] ; then
		echo "skipping whitelisted servers"
		another="n"
	else
		read -p "add whitelisted servers? [y/N] " another
	fi
fi

if [ "$another" = "Y" ] || [ "$another" = "y" ] ; then
	add_server=1
	sed -i "s/#federation_domain_whitelist\:/federation_domain_whitelist\:/" $synapse_conf
else
	add_server=0
fi

while [ $add_server -eq 1 ] ; do
	if [ $predefined_synapse_whitelist -eq 1 ] ; then
		# get next predefined server
		server="${synapse_whitelisted_servers[whitelist_index]}"
		(( whitelist_index++ ))
		if [ ${#synapse_whitelisted_servers[@]} -eq $server_index ] ; then
			add_server=0
		else
			add_server=1
		fi
	else
		echo "enter server hostname"
		read server
		read -p "add another whitelisted server? [y/N] " another
		if [ "$another" = "Y" ] || [ "$another" = "y" ] ; then
			add_server=1
		else
			add_server=0
		fi
	fi

	sed -i "s/#  \- lon.example.com/  \#- lon\.example\.com\
/  \- ${server//./\\./}/"  $synapse_conf
done

# forwarded for
sed -i "s/x_forwarded: false/x_forwarded: true/" /etc/matrix-synapse/homeserver.yaml

while [ -z "$synapse_admin_contact" ] ; do
	echo "enter the mail to use for synapse admin contact (e.g. admin@localhost.net)"
	read synapse_admin_contact
done
synapse_admin_contact="${synapse_admin_contact//./\\.}"
synapse_admin_contact="${synapse_admin_contact//-/\\-}"
synapse_admin_contact="${synapse_admin_contact//@/\\@}"
sed -i "s/#admin_contact: 'mailto:admin@server.com'/admin_contact: 'mailto:${synapse_admin_contact}'/" $synapse_conf

# database
sed -i "s/    database\:/    database\: \/etc\/matrix\-synapse\/${synapse_server_hostname_underscores}\/homeserver\.db\n\#    database\:/" $synapse_conf

# media
sed -i "s/media_store_path\:/media_store_path\: \"\/etc\/matrix\-synapse\/${synapse_server_hostname_underscores}\/media_store\"\n#media_store_path\:/" $synapse_conf

# uploads
sed -i "s/uploads_path\:/uploads_path\: \"\/etc\/matrix\-synapse\/${synapse_server_hostname_underscores}\/uploads\"\n#uploads_path\:/" $synapse_conf

#TODO max upload size
#sed -i "s/max_upload_size\: \"10M\"/max_upload_size\: \"25M\"/" $synapse_conf

# url previews
echo "url previews"
sed -i "s/url_preview_enabled: False/url_preview_enabled: ${synapse_url_preview_enabled}/" $synapse_conf

sed -i "s/#url_preview_ip_range_blacklist:/url_preview_ip_range_blacklist:/" $synapse_conf
sed -i "s/#  - '127\.0\.0\.0\/8'/  - '127\.0\.0\.0\/8'/" $synapse_conf
sed -i "s/#  - '10\.0\.0\.0\/8'/  - '10\.0\.0\.0\/8'/" $synapse_conf
sed -i "s/#  - '172\.16\.0\.0\/12'/  - '172\.16\.0\.0\/12'/" $synapse_conf
sed -i "s/#  - '192\.168\.0\.0\/16'/  - '192\.168\.0\.0\/16'/" $synapse_conf
sed -i "s/#  - '100\.64\.0\.0\/10'/  - '100\.64\.0\.0\/10'/" $synapse_conf
sed -i "s/#  - '169\.254\.0\.0\/16'/  - '169\.254\.0\.0\/16'/" $synapse_conf
sed -i "s/#  - '::1\/128'/  - '::1\/128'/" $synapse_conf
sed -i "s/#  - 'fe80::\/64'/  - 'fe80::\/64'/" $synapse_conf
sed -i "s/#  - 'fc00::\/7'/  - 'fc00::\/7'/" $synapse_conf
sed -i "s/\#turn_shared_secret\: \"YOUR_SHARED_SECRET\"/turn_shared_secret\: \"${turn_shared_secret}\"/" $synapse_conf

#TODO registration shared secret
#registration_shared_secret: ""

#TODO default identity server
#echo "default identity server"
#sed -i "s/default_identity_server: https:\/\/matrix.org/default_identity_server: https:\/\/${identity_server_hostname}/" /home/matrix-synapse/synapse/homeserver.yaml

#TODO third party id servers
#"trusted_third_party_id_servers:"
#"  - matrix.org"
#"  - vector.im"

# signing key
if [ -n "$synapse_signing_key" ] ; then
	echo "${synapse_signing_key}">${synapse_install_dir}/${synapse_server_hostname}.signing.key
fi

# password secret pepper
sed -i "s/   #pepper: \"\"/   pepper: \"${synapse_password_pepper}\"/" /home/matrix-synapse/synapse/homeserver.yaml

#TODO configure email?
#TODO configure user consent?

# no tls
echo -e "\nno_tls: True\n">>$synapse_conf

echo "creating synapse vhost"

if [ -z "$synapse_external_reverse_proxy" ] || [ $synapse_external_reverse_proxy = 3 ] ; then
	reverse_proxy=""
	while [ -z "$reverse_proxy" ] ; do
		read -p "will synapse be served by an external reverse proxy which you will configure manually? [Y/n]" reverse_proxy
		if [ "$reverse_proxy" = "N" ] || [ "$reverse_proxy" = "n" ] ; then
			synapse_external_reverse_proxy=0
		else
			synapse_external_reverse_proxy=1
		fi
	done
fi

# reverse proxy
# .well-known/matrix/server
synapse_server_json_path="/var/www/synapse_server_${synapse_server_hostname_underscores}.json"
synapse_server_json_alias="Alias /.well-known/matrix/server ${synapse_server_json_path}"
echo "{\"m.server\": \"${synapse_server_hostname}:${synapse_server_port}\"}">$synapse_server_json_path
if [ $synapse_external_reverse_proxy = 1 ] ; then
	echo "external reverse proxy to synapse (use local non-ssl reverse proxy)"
	echo "<VirtualHost *:80>
		ServerName ${synapse_server_hostname}
		${synapse_server_json_alias}
		AllowEncodedSlashes NoDecode
		ProxyPass /_matrix http://localhost:8008/_matrix nocanon
		ProxyPassReverse /_matrix http://localhost:8008/_matrix
	</VirtualHost>">"/etc/apache2/sites-available/${synapse_server_hostname}.conf"
else
	echo "standalone ssl reverse proxy to synapse"

	# install let's encrypt certbot
	apt-get install -y certbot

	# create .well-known directories
	mkdir /var/www/html/.well-known
	mkdir /var/www/html/.well-known/acme-challenge

	# create a let's encrypt config to map where the .well-known directory is
	echo "Alias /.well-known/acme-challenge/ \"/var/www/html/.well-known/acme-challenge/\"
<Directory \"/var/www/html/\">
	AllowOverride None
	Options MultiViews Indexes SymLinksIfOwnerMatch IncludesNoExec
	Require method GET POST OPTIONS
</Directory>">/etc/apache2/conf-available/le.conf
	a2enconf le

	echo "<VirtualHost *:80>
		ServerName ${synapse_server_hostname}
	</VirtualHost>">"/etc/apache2/sites-available/${synapse_server_hostname}.conf"
	systemctl restart apache2

	# set up letsencrypt certificate
	certbot certonly --non-interactive -m "${le_registration_mail}" --agree-tos --expand --webroot --webroot-path /var/www/html --domain ${synapse_server_hostname}

	a2enmod ssl
	echo "<IfModule mod_ssl.c>
	<VirtualHost *:443>
		SSLEngine on
		ServerName ${synapse_server_hostname}
		${synapse_server_json_alias}
		SSLCertificateFile /etc/letsencrypt/live/${synapse_server_hostname}/fullchain.pem
		SSLCertificateKeyFile /etc/letsencrypt/live/${synapse_server_hostname}/privkey.pem

		SSLProxyEngine On

		AllowEncodedSlashes NoDecode
		ProxyPass /_matrix http://localhost:8008/_matrix nocanon
		ProxyPassReverse /_matrix http://localhost:8008/_matrix
	</VirtualHost>
	<VirtualHost *:8448>
		SSLEngine on
		ServerName ${synapse_server_hostname}
		${synapse_server_json_alias}
		SSLCertificateFile /etc/letsencrypt/live/${synapse_server_hostname}/fullchain.pem
		SSLCertificateKeyFile /etc/letsencrypt/live/${synapse_server_hostname}/privkey.pem

		SSLProxyEngine On

		AllowEncodedSlashes NoDecode
		ProxyPass /_matrix http://localhost:8008/_matrix nocanon
		ProxyPassReverse /_matrix http://localhost:8008/_matrix
	</VirtualHost>
</IfModule>">>"/etc/apache2/sites-available/${synapse_server_hostname}.conf"
fi
a2ensite ${synapse_server_hostname}
systemctl restart apache2

echo "synapse start and stop scripts"
echo "sudo runuser --user matrix-synapse synctl start ${synapse_conf}">"${synapse_install_dir}/start.sh"
echo "synctl stop ${synapse_conf}">"${synapse_install_dir}/stop.sh"
chmod +x "${synapse_install_dir}/start.sh"
chmod +x "${synapse_install_dir}/stop.sh"

cp /etc/matrix-synapse/log.yaml "${synapse_install_dir}/${matrix_server_hostname}.log.config"

chown -R matrix-synapse $synapse_install_dir

echo "starting synapse"
"${synapse_install_dir}/start.sh"

# admin user
while [ -z "$synapse_admin_user_name" ] ; do
	echo "enter the synapse admin user name (e.g. admin)"
	read synapse_admin_user_name
done
while [ -z "$synapse_admin_user_pass" ] ; do
	echo "enter the synapse admin user pass"
	read synapse_admin_user_pass
done
echo "registering admin user"
register_new_matrix_user -u "${synapse_admin_user_name}" -p "${synapse_admin_user_pass}" -a -c $synapse_conf http://localhost:8008

#TODO additional users

################################################################################
################################################################################
################################################################################
################################################################################

# set up integrations server

# install npm
apt-get install -y nodejs npm
npm i npm@latest -g

# install git
apt-get install -y git

# install dimension
useradd -m matrix-dimension
mkdir /home/matrix-dimension/opt
cd /home/matrix-dimension/opt
git clone https://github.com/turt2live/matrix-dimension.git
chown -R matrix-dimension:matrix-dimension /home/matrix-dimension
cd matrix-dimension

runuser --user matrix-dimension npm install

# fix any high severity advisories
runuser --user matrix-dimension npm audit
runuser --user matrix-dimension npm audit fix

runuser --user matrix-dimension npm run build

while [ -z "$integrations_server_hostname" ] ; do
	echo "enter the server hostname of the integrations server (e.g. integrations.localhost.net)"
	read integrations_server_hostname
done

if [ -z "$dimension_external_reverse_proxy" ] || [ $dimension_external_reverse_proxy = 3 ] ; then
	reverse_proxy=""
	while [ -z "$reverse_proxy" ] ; do
		read -p "will dimension be served by an external reverse proxy which you will configure manually? [Y/n]" reverse_proxy
		if [ "$reverse_proxy" = "N" ] || [ "$reverse_proxy" = "n" ] ; then
			dimension_external_reverse_proxy=0
		else
			dimension_external_reverse_proxy=1
		fi
	done
fi

# reverse proxy
if [ $dimension_external_reverse_proxy = 1 ] ; then
	echo "external reverse proxy to dimension (use local non-ssl reverse proxy)"
	echo "<VirtualHost *:80>
		ServerName ${integrations_server_hostname}
		ProxyPass / http://localhost:8184/
		ProxyPassReverse / http://localhost:8184/
	</VirtualHost>">"/etc/apache2/sites-available/${integrations_server_hostname}.conf"
else
	echo "standalone ssl reverse proxy to dimension"

	# install let's encrypt certbot
	apt-get install -y certbot

	# create .well-known directories
	mkdir /var/www/html/.well-known
	mkdir /var/www/html/.well-known/acme-challenge

	# create a let's encrypt config to map where the .well-known directory is
	echo "Alias /.well-known/acme-challenge/ \"/var/www/html/.well-known/acme-challenge/\"
<Directory \"/var/www/html/\">
	AllowOverride None
	Options MultiViews Indexes SymLinksIfOwnerMatch IncludesNoExec
	Require method GET POST OPTIONS
</Directory>">/etc/apache2/conf-available/le.conf
	a2enconf le

	echo "<VirtualHost *:80>
		ServerName ${integrations_server_hostname}
	</VirtualHost>">"/etc/apache2/sites-available/${integrations_server_hostname}.conf"
	systemctl restart apache2

	# set up letsencrypt certificate
	certbot certonly --non-interactive -m "${le_registration_mail}" --agree-tos --expand --webroot --webroot-path /var/www/html --domain ${integrations_server_hostname}

	a2enmod ssl
	echo "<IfModule mod_ssl.c>
	<VirtualHost *:443>
		SSLEngine on
		ServerName ${integrations_server_hostname}
		SSLCertificateFile /etc/letsencrypt/live/${integrations_server_hostname}/fullchain.pem
		SSLCertificateKeyFile /etc/letsencrypt/live/${integrations_server_hostname}/privkey.pem

		SSLProxyEngine On

		ProxyPass / http://localhost:8184/
		ProxyPassReverse / http://localhost:8184/
	</VirtualHost>
</IfModule>">>"/etc/apache2/sites-available/${integrations_server_hostname}.conf"
fi
a2ensite "${integrations_server_hostname}"
systemctl restart apache2

# screen for starting dimension
echo "installing screen"
apt-get install -y screen

# start, stop, and update scripts
echo "#!/bin/bash
cd /home/matrix-dimension/opt/matrix-dimension
NODE_ENV=production npm run start:apponly">/home/matrix-dimension/run.sh
chmod +x /home/matrix-dimension/run.sh
#NODE_ENV=production npm run start:app">/home/matrix-dimension/run.sh

echo "#!/bin/bash
/home/matrix-dimension/stop.sh
sudo echo \"running dimension\"
runuser --user matrix-dimension -- screen -dmS dimension /home/matrix-dimension/run.sh">/home/matrix-dimension/start.sh
chmod +x /home/matrix-dimension/start.sh

echo "#!/bin/bash
echo \"stopping any existing dimension screen\"
runuser --user matrix-dimension -- screen -X -S dimension quit">/home/matrix-dimension/stop.sh
chmod +x /home/matrix-dimension/stop.sh

echo "#!/bin/bash
cd /home/matrix-dimension/opt/matrix-dimension
/home/matrix-dimension/stop.sh
runuser --user matrix-dimension git pull
runuser --user matrix-dimension npm run build
/home/matrix-dimension/start.sh">/home/matrix-dimension/update.sh
chmod +x /home/matrix-dimension/update.sh

cp /home/matrix-dimension/opt/matrix-dimension/config/default.yaml /home/matrix-dimension/opt/matrix-dimension/config/production.yaml

chown -R matrix-dimension /home/matrix-dimension

dimension_conf=/home/matrix-dimension/opt/matrix-dimension/config/production.yaml

# dimension bot user
while [ -z "$dimension_bot_user_name" ] ; do
	echo "enter the dimension bot user name (e.g. dimension)"
	read dimension_bot_user_name
done

# generate random pass for dimension bot user
dimension_bot_user_pass="$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1)"
echo "registering dimension bot user"
register_new_matrix_user -u "${dimension_bot_user_name}" -p "${dimension_bot_user_pass}" -a -c $synapse_conf http://localhost:8008

# sqlite query to get dimension bot user access token
apt-get install -y sqlite3

synapse_db_path="/etc/matrix-synapse/${synapse_server_hostname_underscores}/homeserver.db"
access_token_query="select \`token\` from \`access_tokens\` where \`user_id\` = \"@${dimension_bot_user_name}:${matrix_server_hostname}\";"
dimension_bot_user_access_token=$(sqlite3 "$synapse_db_path" "${access_token_query}")

# stickers bot user
while [ -z "$stickers_bot_user_name" ] ; do
	echo "enter the stickers bot user name (e.g. stickers)"
	read stickers_bot_user_name
done

# generate random pass for stickers bot user
stickers_bot_user_pass="$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1)"
echo "registering stickers bot user"
register_new_matrix_user -u "${stickers_bot_user_name}" -p "${stickers_bot_user_pass}" -a -c $synapse_conf http://localhost:8008

while [ -z "$dimension_sticker_manager_url" ] ; do
	echo "enter the dimension sticker manager url (e.g. stickers.localhost.net)"
	read dimension_sticker_manager_url
done

# homeserver name to synapse server hostname
sed -i "s/name\: \"t2bot\.io\"/name\: \"${synapse_server_hostname//./\\.}\"/" $dimension_conf
# client server url to synapse server hostname
sed -i "s/clientServerUrl\: \"https\:\/\/t2bot\.io\"/clientServerUrl\: \"https\:\/\/${synapse_server_hostname//./\\.}\"/" $dimension_conf
# dimension bot user access token
sed -i "s/accessToken\: \"something\"/accessToken\: \"${dimension_bot_user_access_token//\-/\\-}\"/" $dimension_conf
# dimension bot user id
sed -i "s/\- \"\@someone\:domain\.com\"/\- \"\@${synapse_admin_user_name}\:${matrix_server_hostname//./\\.}\"/" $dimension_conf
# subdirectory for data?
#sed -i "s/file\: \"dimension\.db\"/file\: \"data\/dimension\.db\"/" $dimension_conf
#sed -i "s/botData\: \"dimension\.bot\.json\"/botData\: \"data\/dimension\.bot\.json\"/" $dimension_conf

#TODO replace icons with local mxc versions instead of t2bot.io versions
#    giphy: "mxc://t2bot.io/c5eaab3ef0133c1a61d3c849026deb27"
#    imgur: "mxc://t2bot.io/6749eaf2b302bb2188ae931b2eeb1513"
#    github: "mxc://t2bot.io/905b64b3cd8e2347f91a60c5eb0832e1"
#    wikipedia: "mxc://t2bot.io/7edfb54e9ad9e13fec0df22636feedf1"
#    travisci: "mxc://t2bot.io/7f4703126906fab8bb27df34a17707a8"
#    rss: "mxc://t2bot.io/aace4fcbd045f30afc1b4e5f0928f2f3"
#    google: "mxc://t2bot.io/636ad10742b66c4729bf89881a505142"
#    guggy: "mxc://t2bot.io/e7ef0ed0ba651aaf907655704f9a7526"
#    echo: "mxc://t2bot.io/3407ff2db96b4e954fcbf2c6c0415a13"
#    circleci: "mxc://t2bot.io/cf7d875845a82a6b21f5f66de78f6bee"
#    jira: "mxc://t2bot.io/f4a38ebcc4280ba5b950163ca3e7c329"

# no telegram bot
sed -i "s/telegram\:/\#telegram\:/" $dimension_conf
sed -i "s/botToken\: \"YourTokenHere\"/#botToken: \"YourTokenHere\"/" $dimension_conf
# sticker bot user id
sed -i "s/stickerBot\: \"\@stickers\:t2bot\.io\"/stickerBot\: \"\@${stickers_bot_user_name}\:${matrix_server_hostname//./\\.}\"/" $dimension_conf
# sticker manager url
dimension_sticker_manager_url="${dimension_sticker_manager_url//./\\.}"
dimension_sticker_manager_url="${dimension_sticker_manager_url//\//\\/}"
dimension_sticker_manager_url="${dimension_sticker_manager_url//\:/\\:}"
dimension_sticker_manager_url="${dimension_sticker_manager_url//\-/\\-}"
sed -i "s/managerUrl\: \"https\:\/\/stickers\.t2bot\.io\"/managerUrl\: \"${dimension_sticker_manager_url}\"/" $dimension_conf
# public url to integrations server hostname
sed -i "s/publicUrl\: \"https\:\/\/dimension\.example\.org\"/publicUrl\: \"https\:\/\/${integrations_server_hostname//./\\.}\"/" $dimension_conf

/home/matrix-dimension/start.sh

#TODO set up to run at system start

################################################################################
################################################################################
################################################################################
################################################################################

# set up web client
useradd -m riot

# install yarn
apt-get install -y curl
curl -sS https://dl.yarnpkg.com/debian/pubkey.gpg | apt-key add -
echo "deb https://dl.yarnpkg.com/debian/ stable main" | tee /etc/apt/sources.list.d/yarn.list
apt update
apt install -y yarn

# ensure yarn can find node even though the package is called nodejs in debian
echo -r "\nalias node=nodejs\n">>/home/riot/.bashrc

mkdir /home/riot/opt
cd /home/riot/opt
git clone https://github.com/vector-im/riot-web.git
chown riot -R /home/riot/opt
cd /home/riot/opt/riot-web
echo "npm doesn't autoresolve dependencies anymore so install the missing dependencies manually"
runuser --user riot -- yarn add babel emojibase react react-dom immutable rollup app-builder-lib typescript matrix-js-sdk
# i don't know why these specific ones don't get pulled in from the yarn add
runuser --user riot -- npm install --save-dev @babel/plugin-proposal-numeric-separator app-builder-lib react @babel/core # react-dom
runuser --user riot -- yarn install
runuser --user riot -- yarn dist
# fix a bunch of broken things?
runuser --user riot -- npm audit fix
runuser --user riot -- npm install

echo "untar dist to /var/www/riot"
tar -C /var/www -zxvf /home/riot/opt/riot-web/dist/riot*.tar.gz
mv /var/www/riot* /var/www/riot

# configure
while [ -z "$riot_server_hostname" ] ; do
	echo "enter the server hostname to serve riot (e.g. chat.localhost.net)"
	read riot_server_hostname
done

while [ -z "$riot_disable_guests" ] ; do
	read -p "disable riot guests? [Y/n] " riot_disable_guests
	if [ "$riot_disable_guests" = "N" ] || [ "$riot_disable_guests" = "n" ] ; then
		riot_disable_guests="false"
	else
		riot_disable_guests="true"
	fi
done

while [ -z "$riot_default_country_code" ] ; do
	echo "enter the default country code for riot (e.g. GB)"
	read riot_default_country_code
done

while [-z "$riot_show_labs_settings" ] ; do
	read -p "show riot labs settings? [Y/n] " riot_show_labs_settings
	if [ "$riot_show_labs_settings" = "N" ] || [ "$riot_show_labs_settings" = "n" ] ; then
		riot_show_labs_settings="false"
	else
		riot_show_labs_settings="true"
	fi
done

while [-z "$riot_default_theme" ] ; do
	echo "enter the default theme for riot "
	read riot_default_theme
done

cp /home/riot/opt/riot-web/config.sample.json /home/riot/config.json
riot_conf=/home/riot/config.json
sed -i "s/\"base_url\"\: \"https\:\/\/matrix\-client\.matrix\.org\",/\"base_url\"\: \"https\:\/\/${synapse_server_hostname//./\\.}\",/" $riot_conf
sed -i "s/\"server_name\"\: \"matrix\.org\"/\"server_name\"\: \"${matrix_server_hostname//.\\.}\"/" $riot_conf
sed -i "s/\"disable_guests\"\: false,/\"disable_guests\"\: ${riot_disable_guests},/" $riot_conf
sed -i "s/\"brand\"\: \"Riot\",/\"brand\"\: \"${riot_brand}\",/" $riot_conf
sed -i "s/\"integrations_ui_url\"\: \"https\:\/\/scalar\.vector\.im\/\",/\"integrations_ui_url\"\: \"https\:\/\/${integrations_server_hostname//./\\.}\/riot\",/" $riot_conf
sed -i "s/\"integrations_rest_url\"\: \"https\:\/\/scalar\.vector\.im\/api\",/\"integrations_rest_url\"\: \"https\:\/\/${integrations_server_hostname//./\\.}\/api\/v1\/scalar\",/" $riot_conf
sed -i "s/\"integrations_widgets_urls\"\:/\"integrations_widgets_urls\"\: \[\"https\:\/\/${integrations_server_hostname//./\\.}\/widgets\"\],\n\"xintegrations_widgets_urls\"\:/" $riot_conf
sed -i "s/\"integrations_jitsi_widget_url\"\: \"https\:\/\/scalar\.vector\.im\/api\/widgets\/jitsi\.html\",/\"integrations_jitsi_widget_url\"\: \"https\:\/\/${integrations_server_hostname//./\\.}\/widgets\/jitsi\",/" $riot_conf
sed -i "s/\"defaultCountryCode\"\: \"GB\",/\"defaultCountryCode\"\: \"${riot_default_country_code}\",/" $riot_conf
sed -i "s/\"showLabsSettings\"\: false,/\"showLabsSettings\"\: ${riot_show_labs_settings},/" $riot_conf
sed -i "s/\"default_theme\"\: \"light\",/\"default_theme\"\: \"${riot_default_theme}\",/" $riot_conf
cp /home/riot/config.json /var/www/riot/config.json
chown riot:riot /var/www/riot/config.json

 # don't cache some riot assets
expires="		<IfModule mod_expires.c>
			ExpiresActive on
			ExpiresDefault \"access plus 1 year\"
			<Location /config.*.json>
				ExpiresActive on
				ExpiresDefault \"access plus 1 second\"
			</Location>
			<Directory /var/www/riot/i18n>
				ExpiresActive on
				ExpiresDefault \"access plus 1 second\"
			</Directory>
			<Directory /var/www/riot/home>
				ExpiresActive on
				ExpiresDefault \"access plus 1 second\"
			</Directory>
			<Directory /var/www/riot/sites>
				ExpiresActive on
				ExpiresDefault \"access plus 1 second\"
			</Directory>
			<Location /index.html>
				ExpiresActive on
				ExpiresDefault \"access plus 1 second\"
			</Location>
		</IfModule>"
https_only="	<Location /index.html>
			<IfModule mod_rewrite.c>
				RewriteEngine On
				RewriteCond %{REQUEST_FILENAME} !-f

				RewriteCond %{HTTPS} !=on
				RewriteRule ^(.*)$ https://%{HTTP_HOST}%{REQUEST_URI} [L,R=301]
			</IfModule>
		</Location>
		<Location /index.html>
			<IfModule mod_rewrite.c>
				RewriteEngine On
				RewriteCond %{REQUEST_FILENAME} !-f

				RewriteCond %{HTTPS} !=on
				RewriteRule ^(.*)$ https://%{HTTP_HOST}%{REQUEST_URI} [L,R=301]
			</IfModule>
		</Location>"

if [ -z "$riot_external_reverse_proxy" ] || [ $riot_external_reverse_proxy = 3 ] ; then
	reverse_proxy=""
	while [ -z "$reverse_proxy" ] ; do
		read -p "will riot be served by an external reverse proxy which you will configure manually? [Y/n]" reverse_proxy
		if [ "$reverse_proxy" = "N" ] || [ "$reverse_proxy" = "n" ] ; then
			riot_external_reverse_proxy=0
		else
			riot_external_reverse_proxy=1
		fi
	done
fi

# reverse proxy
if [ $riot_external_reverse_proxy = 1 ] ; then
	echo "external reverse proxy to riot (use local non-ssl reverse proxy)"
	a2enmod rewrite
	echo "<VirtualHost *:80>
		ServerName ${riot_server_hostname}
		DocumentRoot /var/www/riot
${expires}
${https_only}
	</VirtualHost>">"/etc/apache2/sites-available/${riot_server_hostname}.conf"
else
	echo "standalone ssl reverse proxy to riot"

	# install let's encrypt certbot
	apt-get install -y certbot

	# create .well-known directories
	mkdir /var/www/html/.well-known
	mkdir /var/www/html/.well-known/acme-challenge

	# create a let's encrypt config to map where the .well-known directory is
	echo "Alias /.well-known/acme-challenge/ \"/var/www/html/.well-known/acme-challenge/\"
<Directory \"/var/www/html/\">
	AllowOverride None
	Options MultiViews Indexes SymLinksIfOwnerMatch IncludesNoExec
	Require method GET POST OPTIONS
</Directory>">/etc/apache2/conf-available/le.conf
	a2enconf le

	a2enmod rewrite
	echo "<VirtualHost *:80>
		ServerName ${riot_server_hostname}

		DocumentRoot /var/www/riot
${expires}
${https_only}
	</VirtualHost>">"/etc/apache2/sites-available/${riot_server_hostname}.conf"
	systemctl restart apache2

	# set up letsencrypt certificate
	certbot certonly --non-interactive -m "${le_registration_mail}" --agree-tos --expand --webroot --webroot-path /var/www/html --domain ${riot_server_hostname}

	a2enmod ssl
	echo "<IfModule mod_ssl.c>
	<VirtualHost *:443>
		SSLEngine on
		ServerName ${riot_server_hostname}
		SSLCertificateFile /etc/letsencrypt/live/${riot_server_hostname}/fullchain.pem
		SSLCertificateKeyFile /etc/letsencrypt/live/${riot_server_hostname}/privkey.pem

		DocumentRoot /var/www/riot
${expires}
	</VirtualHost>
</IfModule>">>"/etc/apache2/sites-available/${riot_server_hostname}.conf"
fi
a2ensite "${riot_server_hostname}"
systemctl restart apache2

#TODO bot segment
# create bot user
#useradd -m matrix-bot

#TODO tiny-matrix-bot
#mkdir /home/github/matrix-org
#cd /home/github/matrix-org
#git clone https://github.com/matrix-org/matrix-python-sdk.git
#mkdir /home/github/4nd3r
#cd /home/github/4nd3r
#git clone https://github.com/4nd3r/tiny-matrix-bot.git
#cp -r /home/github/4nd3r/tiny-matrix-bot /home/matrix-bot
#cd /home/matrix-bot/tiny-matrix-bot
#ln -s /home/github/matrix-org/matrix-python-sdk/matrix_client
#cp tiny-matrix-bot.cfg.sample tiny-matrix-bot.cfg
#TODO set cfg base_url, token, scripts_path, enabled_scripts, and inviter
#cp /home/matrix-bot/tiny-matrix-bot/tiny-matrix-bot.service /etc/systemd/system
#TODO set systemctl to use matrix-bot as User
#TODO set systemctl to use /home/matrix-bot/tiny-matrix-bot/tiny-matrix-bot.py as ExecStart
#systemctl enable tiny-matrix-bot
#systemctl start tiny-matrix-bot

#TODO matrix-nio

exit 0
