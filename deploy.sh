#!/bin/bash/
#Functie:	Deployt applicatie in Google Cloud, bestaande uit Linux server instance, Cloud SQL db, Cloud Storage bucket
#Auteur:	jari.wynants@student.kdg.be#	
#Argumenten:	-i or --import:		imports db from storage bucket
#		-d or --delete:		deletes server, db and firewall rules
#		-da or --deleteall:	deletes server, db, firewall rules, reserved IP addresses and storage bucket
#Requirements:	gcloud installed, mysql-client installed

#help functie
if [ "$1" -eq "-h" ] -o [ "$1" -eq "--help" ]; then
	echo "Usage: deploy.sh (-i/-d/-da)"
	echo "Example: 'deploy.sh -i' will create linux server instance, cloud SQL db, Cloud Storage bucket and import db from storage bucket"
fi

if [ $# -eq 0 ]; then	
	#Linux VM instance, SQL instance, firewall rule aanmaken	
	echo "Server wordt aangemaakt..."	
	gloud --image-family=ubuntu-1804-lts --zone=europe-west1-b --metadata=startup-script=startup.sh	gcloud compute instances create deploymentserver --machine-type=g1-small --image-project=ubuntu-os-cloud \	 		
fi

if [ "$1" -eq "-d" ] -o [ "$1" -eq "--delete" ]; then
	echo "Server wordt verwijderd..."	
	gcloud compute instances delete deploymentserver	
fi



