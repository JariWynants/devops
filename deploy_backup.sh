#!/bin/bash
#Functie:	Deployt Google Cloud server bestaande uit Linux server instance, Cloud SQL db, Cloud Storage bucket om .NET core MVC website te runnen
#Auteur:	jari.wynants@student.kdg.be
#Argumenten:	-i or --import:		imports db from storage bucket
#		-d or --delete:		deletes server, db and firewall rules
#		-da or --deleteall:	deletes server, db, firewall rules, reserved IP addresses and storage bucket
#Requirements:	gcloud installed, mysql-client installed

SERVERIP=0

RESERVED_IP_ADDRESS=""
SERVERNAME=deploymentserver
SERVERTYPE=g1-small
SQLNAME=sqlinstance8
ZONE=europe-west1-b
SQLTIER=db-g1-small
REGION=europe-west1
BUCKETNAME=coi-burgers2
DBNAME=coidb

add_image(){
	echo "Server is being set up..."
	if [[ -z $RESERVED_IP_ADDRESS ]]; then
		if [[ -z `gcloud compute addresses list --filter "coi-address"` ]]; then
			echo "New IP address is being created..."
			gcloud compute addresses create coi-address --region=$REGION
		fi
		export RESERVED_IP_ADDRESS=`gcloud compute addresses list --filter "coi-address" | grep -E -o "([0-9]{1,3}[\.]){3}[0-9]{1,3}"` 
	fi
	
	if [[ -z `gcloud compute firewall-rules list | grep "http"` ]]; then
		echo ""
		echo "Creating firewall-rules..."
		gcloud compute firewall-rules create http80 --allow=tcp:80 --target-tags=ds --quiet
		gcloud compute firewall-rules create http8080 --allow=tcp:8080 --target-tags=ds --quiet
	fi

	if [[ -z `gcloud compute firewall-rules list | grep "html"` ]]; then
		gcloud compute firewall-rules create html5000 --allow=tcp:5000 --target-tags=ds --quiet
		gcloud compute firewall-rules create html5001 --allow=tcp:5001 --target-tags=ds --quiet
	fi

	echo ""
	echo "SQL instance is being created..."
        #gcloud sql instances create $SQLNAME --tier=$SQLTIER --region=$REGION --backup-start-time 00:00 --authorized-networks=$RESERVED_IP_ADDRESS &> $HOME/coi-git/deploy.log
	sleep 5
	SQLIP="`gcloud sql instances list | awk '{ if(NR==2){ print $5; } }'`"
	echo ""
	echo "Compute engine is being set up..."

	gcloud compute instances create $SERVERNAME --machine-type=$SERVERTYPE --image-project=ubuntu-os-cloud --image-family=ubuntu-1804-lts --zone=$ZONE --address=$RESERVED_IP_ADDRESS --tags=ds --metadata startup-script="
	#!/bin/bash

	#Install dotnetcore runtime for deployment of .NET application
	#-------------------------------------------------------------
	touch /startup.log
	export DOTNET_CLI_HOME=/ &>> /startup.log

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
	#apt-get -y install mosquitto &>> /startup.log
	#apt-get -y install mosquitto-clients &>> /startup.log
	
	#touch /etc/mosquitto/mosquitto.conf
	#cat > \"/etc/mosquitto/mosquitto.conf\" <<-EOF
	#	pid_file /var/run/mosquitto.pid
	#	persistence true
	#	persistence_location /var/lib/mosquitto
	#	log_dest file /var/log/mosquitto/mosquitto.log
	#	allow_anonymous false
	#	password_file /etc/mosquitto/pwfile
	#	listener 1883
	#EOF
	#mosquitto_passwd -b -c /etc/mosquitto/pwfile deburgers root

	#Install nodejs & npm
	#--------------------
	apt-get -y install nodejs
	apt-get -y install npm

	#Install mysql-client
	#--------------------
	#apt-get -y install mysql-client

	#Clone git project to server
	#---------------------------
	git clone -b depwithsecrets --single-branch https://874a9ff07ffba083c990c89d384408ba6f0f844e@github.com/kdgtg97/city-of-ideas.git &>> /startup.log
	sed -i \"s/server=;port=3306;database=city-of-ideas-db;user=wortel;password=root/server=$SQLIP;port=3306;database=$DBNAME;user=root;password=burgers/g\" /city-of-ideas/DAL/EF/CityOfIdeasDbContext.cs
	sed -i \"s/optionsBuilder.UseSqlite/\\/\\/optionsBuilder.UseSqlite/g\" /city-of-ideas/DAL/EF/CityOfIdeasDbContext.cs
	sed -i \"s/\\/\\/            optionsBuilder.UseMySql/              optionsBuilder.UseMySql/g\" /city-of-ideas/DAL/EF/CityOfIdeasDbContext.cs
	
	#Apache installeren (reverse proxy)
	#----------------------------------
	apt-get -y install apache2 &>> /startup.log
	a2enmod proxy proxy_http proxy_html &>> /startup.log
	a2enmod ssl &>> /startup.log

	#Apache conf file instellen
	#--------------------------
	cat > \"/etc/apache2/conf-enabled/coi.conf\" <<-FOE
		<VirtualHost *:80>
			ServerName cityofideas.ga
			ServerAlias www.cityofideas.ga
			
			#Redirect / https://$RESERVED_IP_ADDRESS/
			ProxyPreserveHost On
			ProxyPass / http://127.0.0.1:5000/
			ProxyPassReverse / http://127.0.0.1:5000/
			ErrorLog /var/log/apache2/coi-error.log
			CustomLog /var/log/apache2/coi-access.log common
		</VirtualHost>

		<VirtualHost *:443>
			ServerAdmin jari.wynants@hotmail.com
			ServerName cityofideas.ga 
			ServerAlias www.cityofideas.ga
	
			ProxyPreserveHost On
			ProxyPass / http://127.0.0.1:5000/
			ProxyPassReverse / http://127.0.0.1:5000/
			ErrorLog /var/log/apache2/coi-error.log
			CustomLog /var/log/apache2/coi-access.log common
		
			SSLEngine on
			SSLCertificateFile /etc/apache2/ssl/apache.crt
			SSLCertificateKeyFile /etc/apache2/ssl/apache.key

			<FilesMatch \"\\.(cgi|shtml|phtml|php)$\">
				SSLOptions +StdEnvVars
			</FilesMatch>
			<Directory /usr/lib/cgi-bin>
				SSLOptions +StdEnvVars
			</Directory>
		</VirtualHost>
	FOE

	echo \"----------- NPM INSTALL -------------\" &>> /startup.log
	(cd /city-of-ideas/COI.UI-MVC/; npm install -g) &>> /startup.log
	(cd /city-of-ideas/COI.UI-MVC/; npm install) &>> /startup.log
	echo \"------------ NPM RUN BUILD -------------\" &>> /startup.log
	(cd /city-of-ideas/COI.UI-MVC/; npm run build) &>> /startup.log
	echo \"------------- DOTNET PUBLISH ---------------\" &>> /startup.log
	#cd /city-of-ideas/COI.UI-MVC/ && dotnet publish &>> /startup.log
	#cp -r /city-of-ideas/COI.UI-MVC/bin/Debug/netcoreapp2.2/publish/ /var/coi &>> /startup.log
	
	#service file instellen
#	cat > \"/etc/systemd/system/kestrel-coi.service\" <<-EO
#		[Unit]
#		Description=City of Ideas dotnet core website running on Ubuntu 18.04
#
#		[Service]
#		WorkingDirectory=/var/coi/
#		ExecStart=/usr/bin/dotnet /var/coi/COI.UI-MVC.dll
#		Restart=always
#		RestartSec=10
#		SyslogIdentifier=dotnet-coi
#		User=apache
#		Environment=ASPNETCORE_ENVIRONMENT=Production
#
#		[Install]	
#		WantedBy=multi-user.target
#	EO

	echo \"help2\" &>> /startup.log

        #HTTPS certificate aanvragen
        #---------------------------
        mkdir /etc/apache2/ssl &>> /startup.log
        openssl req -x509 -newkey rsa:2048 -keyout /etc/apache2/ssl/apache.key -out /etc/apache2/ssl/apache.crt -days 365 -nodes -subj '/C=BE/ST=Antwerp/L=Antwerp/O=KdG/OU=Toegepaste informatica/CN=$RESERVED_IP_ADDRESS' &>> /startup.log	
	service apache2 restart &>> /startup.log
	
	#systemctl enable kestrel-coi.service &>> /startup.log
	#systemctl start kestrel-coi.service &>> /startup.log

	export DOTNET_USER_SECRETS_FALLBACK_DIR=/city-of-ideas/COI.UI-MVC/
	echo \"\$DOTNET_USER_SECRETS_FALLBACK_DIR\" &>> /startup.log
        (cd /city-of-ideas/COI.UI-MVC/; dotnet user-secrets set \"Authentication:Google:ClientId\" \"355723272104-8uddpjediv7gmc9kr3mboduv60atvo7n.apps.googleusercontent.com\") &>> /startup.log
        (cd /city-of-ideas/COI.UI-MVC/; dotnet user-secrets set \"Authentication:Google:ClientSecret\" \"RvmDaMohNqHCgc9IsF0BUsrO\") &>> /startup.log
        (cd /city-of-ideas/COI.UI-MVC/; dotnet user-secrets set \"Authentication:Facebook:AppId 300003197602458)
        (cd /city-of-ideas/COI.UI-MVC/; dotnet user-secrets set \"Authentication:Facebook:AppSecret fe029679748a1f9fc6f8841898a31383)

	#nohup dotnet /var/coi/COI.UI-MVC.dll --urls=http://*:5000 &>> /startup.log 
	nohup dotnet run --project=/city-of-ideas/COI.UI-MVC/COI.UI-MVC.csproj --urls=http://*:5000 &>> /startup.log &
	
	" &> $HOME/coi-git/deployip.log

	echo ""
	echo "Configuring SQL instance..."
	#gcloud sql databases create $DBNAME --instance=$SQLNAME
	#gcloud sql users set-password root --host=% --instance=$SQLNAME --password=burgers
	echo ""
	echo "Storage bucket wordt aangemaakt..."
	#gsutil mb gs://$BUCKETNAME &>> $HOME/coi-git/deploy.log
}

delete_image(){
	echo ""
	read -p "Wilt u de databank exporteren? [Y/n]: " yn
	case $yn in
		[Yy]* )
			gsutil rm gs://$BUCKETNAME/*
		       	SAEMAIL=`gcloud sql instances describe $SQLNAME | grep serviceAccountEmailAddress | cut -d' ' -f2-`
			gsutil acl ch -u $SAEMAIL:W gs://$BUCKETNAME
			gcloud sql export sql $SQLNAME gs://$BUCKETNAME/sqldumpfile.gz --database=$DBNAME
			;;
		[Nn]* ) 
			;;
		* ) 
			echo "Gelieve Yes of No te antwoorden."
			;;
	esac
	echo ""
	echo "Server wordt verwijderd..."
        gcloud compute instances delete $SERVERNAME
        echo ""
	echo "SQL instance wordt verwijderd..."
        gcloud sql instances delete $SQLNAME

		
}

import_db(){
	add_image
	echo ""
	echo "Database wordt geïmporteerd..."
      	SAEMAIL=`gcloud sql instances describe $SQLNAME | grep serviceAccountEmailAddress | cut -d' ' -f2-`
	gsutil acl ch -u $SAEMAIL:W gs://$BUCKETNAME
	gsutil acl ch -u $SAEMAIL:R gs://$BUCKETNAME/sqldumpfile.gz 
	gcloud sql import sql $SQLNAME gs://$BUCKETNAME/sqldumpfile.gz --database=$DBNAME
}

delete_all(){
	delete_image
	#TODO "Gereserveerd IP adres en storage bucket wordt verwijderd..."	
	echo ""
	echo "Bucket wordt verwijderd..."
	gsutil rm -r gs://$BUCKETNAME &>> $HOME/coi-git/deploy.log
	echo ""
	echo "Reserved IP addresses are deleted..."
	gcloud compute addresses delete coi-address --region=$REGION
	echo ""
	echo "Firewall rules are deleted..."
	gcloud compute firewall-rules delete html5000 html5001 http80 http8080
}

#help functie
if [[ "$1" == "-h" || "$1" == "--help" || $# -ge 2 ]]; then
	echo "Usage: deploy.sh (-i/-d/-da)"
	echo "Example: 'deploy.sh -i' will create linux server instance, cloud SQL db, Cloud Storage bucket and import db from storage bucket"
	exit 0
fi

if [[ $# -eq 0 ]]; then
#Create Linux VM instance, SQL instance, firewall rule
	add_image
fi

if [[ "$1" == "-d" ]] || [[ "$1" == "--delete" ]]; then
#Delete VM instance, SQL instance and firewall rule
	delete_image
fi

if [[ "$1" == "-i" ]] || [[ "$1" == "--insert" ]]; then
#add_image + import database
	import_db
fi

if [[ "$1" == "-da" ]] || [[ "$1" == "--deleteall" ]]; then
#delete_image + reserved IP addresses + storage bucket
	delete_all 
fi
