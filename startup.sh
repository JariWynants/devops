#!/bin/bash
#Functie:	Startup script voor deployment server
#Auteur:	jari.wynants@student.kdg.be
#Argumenten:	/
#Requirements:	/

#Install dotnetcore runtime for deployment of .NET application
#-------------------------------------------------------------
touch /startup.log

dpkg -i packages-microsoft-prod.deb wget -q https://packages.microsoft.com/config/ubuntu/18.04/packages-microsoft-prod.deb

apt-get -y install apt-transport-https &>> /startup.log
add-apt-repository universe &>> /startup.log
apt-get -y update &>> /startup.log
apt-get -y install dotnet-sdk-2.1 &>> /startup.log

#Install Moqsuitto MQTT Broker for connection with LoRa
#------------------------------------------------------
#TODO: open port 1883 to allow connection (in deploy.sh)

apt-add-repository ppa:mosquitto-dev/mosquitto-ppa &>> /startup.log
apt-get -y install mosquitto &>> /startup.log
apt-get -y install mosquitto-clients &>> /startup.log

#Clone git project to server
#---------------------------
git clone https://874a9ff07ffba083c990c89d384408ba6f0f844e@github.com/kdgtg97/city-of-ideas.git &>> /startup.log

#Deploy .NET application on server
#---------------------------------
apt-get -y install apache2 &>> /startup.log
a2enmod proxy proxy_http proxy_html &>> /startup.log

#TODO: log file instellen

service apache2 restart &>> /startup.log
dotnet publish /city-of-ideas &>> /startup.log
cp -a /city-of-ideas/COI.UI-MVC/bin/Debug/netcoreapp2.1/publish /var/coi &>>/startup.log
#TODO: service file instellen
systemctl enable kestrel-coi.service &>> /startup.log
systemctl start kestrel-coi.service &>> /startup.log









