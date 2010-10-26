#!/usr/bin/perl
#############################################################################################################
# Script Name:	Git Auto deploy
# Author: 	Guillaume Seigneuret
# Date: 	10.26.2010
# Version:	0.2
# 
# Usage:	Execute it via crontab or shell prompt, no args
# 
# Usage domain: Works for every web application using MySQL or not.
# 		Also works for basic application without complex dependant environment. 
# 
# Config: 	Every parameters must be described in the config file
# 
# Config file:	Must be the name of the script (with .config or rc extension), 
# 		located in /etc or the same path as the script
# 
# MySQL update: The SQL update file can be anywhere in the project tree but must have the "update" keyword
# 		in filename to be applied. Be sure to not delete your data while updating the DB...
#
# Permission file: The permission file can be placed in the project tree, it must be named project.permission
# 		The script will apply the specified permissions to the files described in it.
# 		default user and group are users and group of the script executer ! be carefull to not
# 		execute it as root unless you exactly now what you're doing.
# 		ex: 
# 		toto.php = rw (will apply the write permission to the web server)
#		titi.exe = rx (will apply the execution permission to all)
#		blah.php = r  (will remove all write or execute permission while letting the read permission)
#		octal also works : 
#############################################################################################################

# TODO 
# Git deploy should :
#       [OK] Get the directory and put script/http files into a specific directory
#       [OK] Download only the last version of the project
#       [OK] Apply only updates if the project already exists
#       - Be able to set file/directory permissions
#       - Be able to look after a sql file and update the database
#       - The database must only be changed in the structure and do not add or delete data/rows
#       - Be able to verify the application environment (Web server config, php, ruby, python config)
#       [OK] Search for new versions
#       - Generate a report of the deployment and send it to concerned poeple by mail.

use strict;
use Config::Auto;
use MIME::Lite;
#use DBD::mysql;
use File::Find;
use Data::Dumper;


my $config = Config::Auto::parse();
        #print Dumper($config);
my $git 	= trim($config->{engine-conf}->{git});
my $mysql 	= trim($config->{engine-conf}->{mysql});

die("Git is not installed\n") unless (-e $git);
print "WARNING : No MySQL client.\n" unless (-e $mysql);

{

	# Create a buffer for logging message during the script execution.
	my @buffer = ();

	# Lets see what project we have to deploy ...
        foreach my $project (keys(%$config)) {

		# This section of the configuration is the core script config
		# Skip it and see next config part.
		next if ($project eq "engine-conf");

		# Loading the project settings
                my $local_path  = trim($config->{$project}->{local_project_path});
                my $depth       = trim($config->{$project}->{depth});
                my $branch      = trim($config->{$project}->{branch});
                my $user        = trim($config->{$project}->{user});
                my $server      = trim($config->{$project}->{server});
                my $git_project = trim($config->{$project}->{git_project});

                # Is the project destination path exists ?
                unless (-e $local_path){
                        lig_this(\@buffer,  "[$project] Your set destination directory does not exists. Create it and rerun the deployment.\n");	
			lig_this(\@buffer,  "[$project] Tried local path : $local_path.\n");
                        next;
                }

                # Is the project is git initted ?
                lig_this($buffer,  "Failed while opening $local_path\n") if (!opendir(DIR, "$local_path/$project/.git"));
                if (!readdir DIR){
                        # No ! I create it.
                        lig_this(\@buffer,  "[$project] Project doesn't exists, creating it...\n");
                        chdir "$local_path";
                        lig_this(\@buffer,  "		cd $local_path\n");
                        lig_this(\@buffer,  "		$git clone --depth=$depth -b $branch $user\@$server:$git_project\n");
                        #print `pwd`;
                        if( system("$git clone --depth=$depth -b $branch $user\@$server:$git_project\n") == 0){
                                lig_this(\@buffer,  "[$project] Project successfully loaded\n");
                                # The project is successfully loaded, I search for a database and I load it.
                                lig_this(\@buffer,  "		Searching for sql file ...\n");
                                find(\&SQLload, "$local_path/$project");
                        }

                }
                else {
                        lig_this(\@buffer,  "[$project] Project still exists, updating it ...\n");
                        lig_this(\@buffer,  "		cd $local_path\n");
                        chdir "$local_path/$project";
                        lig_this(\@buffer,  "[$project] Trying to update ...\n");
                        my $status = `$git pull`;
                        chomp($status);
                        if ($status ne "Already up-to-date."){
                                find(\&SQLload, "$local_path/$project");
                        }
                        else {
                                lig_this(\@buffer,  "[$project] Already up to date.\n");
                        }
                }
        }
}

sub SQLload {
        my $file = $File::Find::name;
	my @files = ();

        if ($file =~ /.*update.*\.sql$/){
                lig_this($buffer,  "		Found SQL update file : $file\n");
		push(@files,$file);
        }

	return @files;
}

sub loaddb {
        my ($host, $port, $db, $user, $pass, $sql_file) = @_;
}

sub set_permissions {
	my ($perm_file) = @_;
}

sub log_this {
	my ($buffer, $message) = @_;
	push(@$buffer, $message);
	print $message;
}

sub trim
{
    my @out = @_;
    for (@out)
    {
        s/^\s+//;
        s/\s+$//;
    }
    return wantarray ? @out : $out[0];
}

sub mail_this {
        my ($recipient, $cc, $title, $message) = @_;

        my $Message = new MIME::Lite (
                From =>'deployment@omegacube.fr',
                To =>$recipient,
                Cc =>$cc,
                Subject =>$title,
                Type =>'TEXT',
                Data =>$message
        );

        $Message -> send;

        return 0;
}

