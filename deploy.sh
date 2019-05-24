#!/bin/bash
#Functie:	Deployt Google Cloud server bestaande uit Linux server instance, Cloud SQL db, Cloud Storage bucket om .NET core MVC website te runnen
#Auteur:	jari.wynants@student.kdg.be
#Argumenten:	-i or --import:		imports db from storage bucket
#		-d or --delete:		deletes server, db and firewall rules
#		-da or --deleteall:	deletes server, db, firewall rules, reserved IP addresses and storage bucket
#Requirements:	gcloud installed, mysql-client installed

server_ip=0
db_password=""
reserved_ip_address=""
server_name=deploymentserver
server_type=g1-small
sql_name=sqlinstance9
zone=europe-west1-b
sql_tier=db-g1-small
region=europe-west1
bucket_name=coi-burgers2
db_name=coidb

add_image(){
	echo "Server is being set up..."
	if [[ -z $reserved_ip_address ]]; then
		if [[ -z `gcloud compute addresses list --filter "coi-address"` ]]; then
			echo "New IP address is being created..."
			gcloud compute addresses create coi-address --region=$region
		fi
		export reserved_ip_address=`gcloud compute addresses list --filter "coi-address" | grep -E -o "([0-9]{1,3}[\.]){3}[0-9]{1,3}"` 
	fi
	
	if [[ -z `gcloud compute firewall-rules list | grep "tcp:80"` ]]; then
		echo ""
		echo "Creating firewall-rules (tcp:80, tcp:8080)"
		gcloud compute firewall-rules create http80 --allow=tcp:80 --target-tags=ds --quiet
		gcloud compute firewall-rules create http8080 --allow=tcp:8080 --target-tags=ds --quiet
	fi

	if [[ -z `gcloud compute firewall-rules list | grep "tcp:443"` ]]; then
		echo "Create firewall-rules (tcp:443)"
		gcloud compute firewall-rules create http443 --allow=tcp:443 --target-tags=ds --quiet
	fi

	if [[ -z `gcloud compute firewall-rules list | grep "tcp:5000"` ]]; then
		echo "Creating firewall-rules (tcp:5000)"
		gcloud compute firewall-rules create html5000 --allow=tcp:5000 --target-tags=ds --quiet
	fi

	if [[ -z `gcloud compute firewall-rules list | grep "tcp:1883"` ]]; then
		echo "Creating firewall-rules (tcp:1883)"
		gcloud compute firewall-rules create mqtt1883 --allow=tcp:1883 --target-tags=ds --quiet
	fi

	echo ""
	echo "SQL instance is being created..."
        gcloud sql instances create $sql_name --tier=$sql_tier --region=$region --backup-start-time 00:00 --authorized-networks=$reserved_ip_address &> $HOME/coi-git/deploy.log
	sleep 5
	sql_ip="`gcloud sql instances list | awk '{ if(NR==2){ print $5; } }'`"
	echo ""
	echo "Compute engine is being set up..."

	gcloud compute instances create $server_name --machine-type=$server_type --image-project=ubuntu-os-cloud --image-family=ubuntu-1804-lts --zone=$zone --address=$reserved_ip_address --tags=ds --metadata startup-script="
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

	#Install mysql-client (optional - to check db connection from server)
	#--------------------
	#apt-get -y install mysql-client

	#Clone git project to server
	#---------------------------
	git clone -b testdatadeploy --single-branch https://874a9ff07ffba083c990c89d384408ba6f0f844e@github.com/kdgtg97/city-of-ideas.git &>> /startup.log
	sed -i \"s/Data Source=CityOfIdeasDb/server=$sql_ip;port=3306;database=$db_name;user=root;password=$db_password/g\" /city-of-ideas/DAL/EF/CityOfIdeasDbContext.cs
	sed -i \"s/optionsBuilder.UseSqlite/optionsBuilder.UseMySql/g\" /city-of-ideas/DAL/EF/CityOfIdeasDbContext.cs
	#sed -i \"s/\\/\\/            optionsBuilder.UseMySql/              optionsBuilder.UseMySql/g\" /city-of-ideas/DAL/EF/CityOfIdeasDbContext.cs
	sed -i \"s/true/false/g\" /city-of-ideas/DAL/EF/CityOfIdeasDbContext.cs

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
			
			#Redirect / https://$reserved_ip_address/
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
	
        #HTTPS certificate aanvragen
        #---------------------------
        mkdir /etc/apache2/ssl &>> /startup.log
        openssl req -x509 -newkey rsa:2048 -keyout /etc/apache2/ssl/apache.key -out /etc/apache2/ssl/apache.crt -days 365 -nodes -subj '/C=BE/ST=Antwerp/L=Antwerp/O=KdG/OU=Toegepaste informatica/CN=$reserved_ip_address' &>> /startup.log	
	service apache2 restart &>> /startup.log
	
	echo \"FINISHED\" &>> /startup.log
	nohup dotnet run --project=/city-of-ideas/COI.UI-MVC/COI.UI-MVC.csproj --urls=http://*:5000 &>> /startup.log &
	
" &> $HOME/coi-git/deployip.log

	#sleep 10
	#while [[ ! `gcloud compute ssh deploymentserver --command="cat /startup.log | grep FINISHED"` ]]; do
	#	sleep 5
	#	echo | set /p "Setting up."
	#	echo | set /p "Setting up.."
	#	echo | set /p "Setting up..."
	#done
	
	echo ""
	echo "Configuring SQL instance..."
	gcloud sql databases create $db_name --instance=$sql_name
	gcloud sql users set-password root --host=% --instance=$sql_name --password=$db_password
	echo ""
	echo "Creating storage bucket..."
	gsutil mb gs://$bucket_name &>> $HOME/coi-git/deploy.log
}

delete_image(){
	echo ""
	read -p "Do you want to export the database? (Y/n): " yn
	case $yn in
		[Yy]* )
			gsutil rm gs://$bucket_name/*
		       	sa_email=`gcloud sql instances describe $sql_name | grep serviceAccountEmailAddress | cut -d' ' -f2-`
			gsutil acl ch -u $sa_email:W gs://$bucket_name
			gcloud sql export sql $sql_name gs://$bucket_name/sqldumpfile.gz --database=$db_name
			;;
		[Nn]* ) 
			;;
		* ) 
			echo "Please answer Y or N."
			;;
	esac
	echo ""
        gcloud compute instances delete $server_name
        echo "SQL server being deleted..."
        gcloud sql instances delete $sql_name

		
}

import_db(){
	add_image
	echo ""
	echo "Database is being imported..."
      	sa_email=`gcloud sql instances describe $sql_name | grep serviceAccountEmailAddress | cut -d' ' -f2-`
	gsutil acl ch -u $sa_email:W gs://$bucket_name
	gsutil acl ch -u $sa_email:R gs://$bucket_name/sqldumpfile.gz 
	gcloud sql import sql $sql_name gs://$bucket_name/sqldumpfile.gz --database=$db_name
}

delete_all(){
	delete_image
	echo ""
	echo "Bucket is being deleted..."
	gsutil rm -r gs://$bucket_name &>> $HOME/coi-git/deploy.log
	echo ""
	echo "Reserved IP addresses are deleted..."
	gcloud compute addresses delete coi-address --region=$region
	echo ""
	echo "Firewall rules are deleted..."
	gcloud compute firewall-rules delete html5000 html5001 http80 http8080
}


#####################################################
################### SCRIPT START ####################
#####################################################

#help function
if [[ "$1" == "-h" || "$1" == "--help" || $# -ge 2 ]]; then
	echo "Usage: deploy.sh (-i/-d/-da)"
	echo "Example: 'deploy.sh -i' will create linux server instance, cloud SQL db, Cloud Storage bucket and import db from storage bucket"
	exit 1
fi

#check if gcloud is installed
error_message="gcloud is not installed on your machine, cannot proceed."
command -v gcloud > /dev/null || echo $error_message
command -v gcloud > /dev/null || exit 1
if [[ $# -eq 0 ]]; then
#Create Linux VM instance, SQL instance, firewall rule
	while [[ -z $db_password ]]; do
		read -p "Enter password (will be used to create database, cannot be empty):" -s db_password
		echo ""
	done
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

