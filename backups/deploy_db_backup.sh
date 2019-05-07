#!/bin/bash
#Functie:	Deployt Google Cloud server bestaande uit Linux server instance, Cloud SQL db, Cloud Storage bucket om .NET core MVC website te runnen
#Auteur:	jari.wynants@student.kdg.be
#Argumenten:	-i or --import:		imports db from storage bucket
#		-d or --delete:		deletes server, db and firewall rules
#		-da or --deleteall:	deletes server, db, firewall rules, reserved IP addresses and storage bucket
#Requirements:	gcloud installed, mysql-client installed

SERVERIP=0
SERVERNAME=deploymentserver
SERVERTYPE=g1-small
SQLNAME=deploymentserver2
ZONE=europe-west1-b
SQLTIER=
REGION=europe-west1
BUCKETNAME=coi-burgers

add_image(){
	echo "Server wordt aangemaakt..."
	gcloud compute instances create deploymentserver --machine-type=g1-small --image-project=ubuntu-os-cloud --image-family=ubuntu-1804-lts --zone=europe-west1-b --metadata-from-file=startup-script=/home/jari/coi-git/startup.sh &> $HOME/coi-git/deployip.log
	echo ""
	echo "SQL instance wordt aangemaakt..."
	SERVERIP="`awk '{ if(NR==3){ print $5; } }' $HOME/coi-git/deployip.log`"
	echo $SERVERIP
	gcloud sql instances create deploymentsql2 --tier=db-f1-micro --region=europe-west1 --backup-start-time 00:00 --authorized-networks="$SERVERIP" &> $HOME/coi-git/deploy.log
	echo ""
	echo "Configuring SQL instance..."
	gcloud sql users set-password root --host=% --instance=deploymentsql2 --password=burgers
	echo ""
	echo "Storage bucket wordt aangemaakt..."
	gsutil mb gs://coi-burgers &>> $HOME/coi-git/deploy.log
}

delete_image(){
	echo "Server wordt verwijderd..."
	gcloud compute instances delete deploymentserver
	echo "SQL instance wordt verwijderd..."
	gcloud sql instances delete deploymentsql2
	
}

import_db(){
	add_image
	#TODO "Database wordt geïmporteerd..."
}

delete_all(){
	delete_image
	#TODO "Gereserveerd IP adres en storage bucket wordt verwijderd..."	
	echo "Bucket wordt verwijderd..."
	gsutil rm -r gs://coi-burgers &>> $HOME/coi-git/deploy.log
}

#help functie
if [ "$1" == "-h" ] || [ "$1" == "--help" ] || [ "$#" >= 2 ]; then
	echo "Usage: deploy.sh (-i/-d/-da)"
	echo "Example: deploy.sh will create linux server instance, cloud SQL db, Cloud Storage bucket and import db from storage bucket"
fi

if [ "$#" == 0 ]; then
#Create Linux VM instance, SQL instance, firewall rule
	add_image
fi

if [ "$1" == "-d" ] || [ "$1" == "--delete" ]; then
#Delete VM instance, SQL instance and firewall rule
	delete_image
fi

if [ "$1" == "-i" ] || ["$1" == "--insert" ]; then
#add_image + import database
	import_db
fi

if [ "$1" == "-da" ] || [ "$1" == "--deleteall" ]; then
#delete_image + reserved IP addresses + storage bucket
	delete_all 
fi
	


	
	





	
