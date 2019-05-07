#!/bin/bash
#Functie:	Startup script voor deployment server
#Auteur:	jari.wynants@student.kdg.be
#Argumenten:	/
#Requirements:	/

#Install dotnetcore runtime for deployment of .NET application
#-------------------------------------------------------------
touch /startup.log
export DOTNET_CLI_HOME=/ &>> /startup.log

echo $DOTNET_CLI_HOME >> /variables.log
wget -q https://packages.microsoft.com/config/ubuntu/18.04/packages-microsoft-prod.deb
dpkg -i packages-microsoft-prod.deb 

add-apt-repository universe &>> /startup.log
apt-get -y install apt-transport-https &>> /startup.log
apt-get -y update &>> /startup.log
apt-get -y install dotnet-sdk-2.2 &>> /startup.log

#Install Moqsuitto MQTT Broker for connection with LoRa
#------------------------------------------------------
#TODO: open port 1883 to allow connection (in deploy.sh)

apt-add-repository ppa:mosquitto-dev/mosquitto-ppa &>> /startup.log
apt-get -y install mosquitto &>> /startup.log
apt-get -y install mosquitto-clients &>> /startup.log

#Install nodejs & npm
#--------------------
apt-get -y install nodejs
apt-get -y install npm

#Install mysql-client
#--------------------
apt-get -y install mysql-client

#Clone git project to server
#---------------------------
git clone -b dependency_injection_deploy --single-branch https://874a9ff07ffba083c990c89d384408ba6f0f844e@github.com/kdgtg97/city-of-ideas.git &>> /startup.log

#Deploy .NET application on server
#---------------------------------
apt-get -y install apache2 &>> /startup.log
a2enmod proxy proxy_http proxy_html &>> /startup.log

#log file instellen
cat > "/etc/apache2/conf-enabled/coi.conf" <<EOF
	<VirtualHost *:80>
	ServerName cityofideas.ga
	ServerAlias www.cityofideas.ga

	ProxyPreserveHost On
	ProxyPass / http://127.0.0.1:5000/
	ProxyPassReverse / http://127.0.0.1:5000/
	ErrorLog /var/log/apache2/coi-error.log
	CustomLog /var/log/apache2/coi-access.log common
	</VirtualHost>
EOF

service apache2 restart &>> /startup.log
(cd /city-of-ideas/COI.UI-MVC && npm install --no-optional) &>> /startup.log
(cd /city-of-ideas/COI.UI-MVC && npm run build) &>> /startup.log
(cd /city-of-ideas/COI.UI-MVC && dotnet publish) &>> /startup.log
cp -a /city-of-ideas/COI.UI-MVC/bin/Debug/netcoreapp2.2/publish /var/coi &>>/startup.log
#service file instellen
cat > "/etc/systemd/system/kestrel-coi.service" <<EOF
	[Unit]
	Description=City of Ideas dotnet core website running on Ubuntu 18.04

	[Service]
	WorkingDirectory=/var/coi
	ExecStart=/usr/bin/dotnet var/coi/COI.UI-MVC.dll
	Restart=always
	RestartSec=10
	SyslogIdentifier=dotnet-coi
	User=apache
	Environment=ASPNETCORE_ENVIRONMENT=Production

	[Install]	
	WantedBy=multi-user.target
EOF

systemctl enable kestrel-coi.service &>> /startup.log
systemctl start kestrel-coi.service &>> /startup.log

#nohup (cd /var/coi && dotnet run --urls=http://*:5000) &>> /startup.log
