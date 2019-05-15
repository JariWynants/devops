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
SQLNAME=sqlinstance3
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
		RESERVED_IP_ADDRESS=`gcloud compute addresses list --filter "coi-address" | grep -E -o "([0-9]{1,3}[\.]){3}[0-9]{1,3}"` 
	fi
	
	if [[ -z `gcloud compute firewall-rules list | grep "http"` ]]; then
		echo ""
		echo "Creating firewall-rules..."
		gcloud compute firewall-rules create http80 --allow=tcp:80 --target-tags=ds
		gcloud compute firewall-rules create http8080 --allow=tcp:8080 --target-tags=ds
	fi

	if [[ -z `gcloud compute firewall-rules list | grep "html"` ]]; then
		gcloud compute firewall-rules create html5000 --allow=tcp:5000 --target-tags=ds
		gcloud compute firewall-rules create html5001 --allow=tcp:5001 --target-tags=ds
	fi

	gcloud compute instances create $SERVERNAME --machine-type=$SERVERTYPE --image-project=ubuntu-os-cloud --image-family=ubuntu-1804-lts --zone=$ZONE --address=$RESERVED_IP_ADDRESS --tags=ds --metadata-from-file=startup-script=/home/jari/coi-git/startup_backup.sh &> $HOME/coi-git/deployip.log
	echo ""
	echo "SQL instance is being set up..."
	SERVERIP="`awk '{ if(NR==3){ print $5; } }' $HOME/coi-git/deployip.log`"
	echo $SERVERIP
	gcloud sql instances create $SQLNAME --tier=$SQLTIER --region=$REGION --backup-start-time 00:00 --authorized-networks="$SERVERIP" &> $HOME/coi-git/deploy.log
	wait
	sleep 10
	gcloud sql databases create $DBNAME --instance=$SQLNAME
	echo ""
	echo "Configuring SQL instance..."
	gcloud sql users set-password root --host=% --instance=$SQLNAME --password=burgers
	echo ""
	echo "Storage bucket wordt aangemaakt..."
	gsutil mb gs://$BUCKETNAME &>> $HOME/coi-git/deploy.log
}

delete_image(){
	echo ""
	read -p "Wilt u de databank exporteren? [Y/n]: " yn
	case $yn in
		[Yy]* )
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
if [[ "$1" -eq "-h" ]] || [[ "$1" -eq "--help" ]] || [[ "$#" -ge "2" ]]; then
	echo "Usage: deploy.sh (-i/-d/-da)"
	echo "Example: deploy.sh will create linux server instance, cloud SQL db, Cloud Storage bucket and import db from storage bucket"
fi

if [[ "$#" -eq "0" ]]; then
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
