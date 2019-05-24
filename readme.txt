########################################################
####### CITY OF IDEAS web app deployment script ########
########################################################

Please execute following instructions on how to run the deployment script and properly set up your web app.

If you're running this script for the first time, please run the script without parameters. Everything will be set up automatically.
To run the script, execute the 'deploy.sh' shell script in the terminal.

This will make a compute instance (which will run the web app), an SQL instance (with a database) and a bucket (to export SQL data).

THIS WILL TAKE A WHILE!!! After the command is finished, you can check the process of the deployment on the compute instance. If you
want to check the progress, please run 'gcloud compute ssh <server_name>' to connect to the server instance. Here you can find a startup.log
file where you can check the progress.
---------------------------------------------------

You can also run the script with the following flags:

deploy.sh

	-d 		: 	this will delete the compute instance and the SQL instance. The bucket will NOT be deleted. 
	-i 		: 	this will import SQL data into the database from previous use.
	-da 		: 	this will delete everything, including the bucket. RUN THIS ONLY IF YOU WANT TO DELETE ABSOLUTELY EVERYTHING.
	-h or --help 	:	this will bring up a basic help command.

If you have your own gcloud IP address reserved, please insert in the script variable. You can also change multiple other variable names if you want to. Keep in mind that names for the SQL instance and bucket name will be reserved for a few days, so you cannot use the same name multiple times in the same few days.
