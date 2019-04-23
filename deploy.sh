#!/bin/bash
#Functie:	Deployt Google Cloud server bestaande uit Linux server instance, Cloud SQL db, Cloud Storage bucket om .NET core MVC website te runnen
#Auteur:	jari.wynants@student.kdg.be
#Argumenten:	-i or --import:		imports db from storage bucket
#		-d or --delete:		deletes server, db and firewall rules
#		-da or --deleteall:	deletes server, db, firewall rules, reserved IP addresses and storage bucket
#Requirements:	gcloud installed, mysql-client installed

add_image(){
	echo "Server wordt aangemaakt..."
	gcloud compute instances create deploymentserver --machine-type=g1-small --image-project=ubuntu-os-cloud --image-family=ubuntu-1804-lts --zone=europe-west1-b --metadata-from-file=startup-script=/home/jari/coi-git/startup.sh &> /home/jari/coi-git/deploy.log
	
	echo "ten seconds to finish..."
	sleep 10
	echo "Applicatie wordt gedeployd..."
	gcloud compute ssh deploymentserver --command "sudo dotnet publish /city-of-ideas" &>> deploy.log
	gcloud compute ssh deploymentserver --command "sudo cp -a /city-of-ideas/COI.UI-MVC/bin/Debug/netcoreapp2.1/publish /var/coi" &>> deploy.log
}

delete_image(){
	echo "Server wordt verwijderd..."
	gcloud compute instances delete deploymentserver
	
}

import_db(){
	add_image
	#TODO "Database wordt geïmporteerd..."
}

delete_all(){
	delete_image
	#TODO "Gereserveerd IP adres en storage bucket wordt verwijderd..."	
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
	


	
	





	
