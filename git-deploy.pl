#!/usr/bin/perl
#############################################################################################################
# Script Name:	Git Auto deploy
# Author: 	Guillaume Seigneuret
# Date: 	13.01.2010
# Last mod	16.01.2011
# Version:	1.1
# 
# Usage:	Execute it via crontab or shell prompt, or with the GSD server.
# 
# Usage domain: Works for every web application using MySQL or not.
# 		Also works for basic application without complex dependant environment. 
# 
# Args :	Optionnal, the name of the project we want to load. If no args, all the projects in
# 		the config file are updated.
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
# 		One CSV value per line. You can use absolute or relative pathes.
# 		Default user and group are users and group of the script executer ! be carefull to not
# 		execute it as root unless you exactly now what you're doing.
# 		ex: 
#		./file.txt,toto,www-data,0660 (will apply read/write permission to toto and www-data users)
#		./images/contenu/image.jpg,toto,www-data,0640 
#
#   Copyright (C) 2012 Guillaume Seigneuret (Omega Cube)
#
#   This program is free software: you can redistribute it and/or modify
#   it under the terms of the GNU General Public License as published by
#   the Free Software Foundation, either version 3 of the License.
#
#   This program is distributed in the hope that it will be useful,
#   but WITHOUT ANY WARRANTY; without even the implied warranty of
#   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#   GNU General Public License for more details.
#
#   You should have received a copy of the GNU General Public License
#   along with this program.  If not, see <http://www.gnu.org/licenses/>		 
#############################################################################################################

# TODO
#
# Git deploy should :
#       [DONE] Get the directory and put script/http files into a specific directory
#       [DONE] Download only the last version of the project
#       [DONE] Apply only updates if the project already exists
#       [DONE] Be able to set file/directory permissions
#       [DONE] Be able to look after a sql file and update the database
#       - The database must only be changed in the structure and do not add or delete data/rows
#       - Be able to verify the application environment (Web server config, php, ruby, python config)
#       [DONE] Search for new versions
#       [DONE] Generate a report of the deployment and send it to concerned poeple by mail.
#       [DONE] Run the script with unprivileged user (change with the config)

use strict;
use Config::Auto;
use MIME::Lite;
#use DBD::mysql;
use File::Find;
use English;
use Data::Dumper;

$| = 1;

our $_PROJECT;
our $_BRANCH;
my $config = Config::Auto::parse();
        #print Dumper($config);
my $git 	= trim($config->{"engine-conf"}->{"git"});
my $mysql 	= trim($config->{"engine-conf"}->{"mysql"});
my $errors_file = trim($config->{"engine-conf"}->{"error_file"});
my $smtp	= trim($config->{"engine-conf"}->{"smtp"});

die("Git is not installed\n") unless (-e $git);
print "WARNING : No MySQL client.\n" unless (-e $mysql);

# Create a buffer for logging message during the script execution.
my @buffer = ();
# Create a global array for the sql file because of this *** find function
my @mysql_files = ();
my @perm_files = ();
my @wp_files = ();

{
	# Redirect STDERR to a buffer.
	open (STDERR,">$errors_file");

	my $project = "";
	$project = $ARGV[0] if(defined trim($config->{$ARGV[0]}));
	if (defined $config->{$_PROJECT} #and 
		#	defined trim($config->{$_PROJECT}->{$_BRANCH}) 
	) {
		$project = $_PROJECT;
	}

	if ($project eq ""){
		print "Unable te deploy anything because nor ARGV0 nor \$_PROJECT was set\n.";
		die "Unable te deploy anything because nor ARGV0 nor \$_PROJECT was set\n.";
	}

	# Loading the project settings
	my $local_path  = trim($config->{$project}->{"local_project_path"});
	my $depth       = trim($config->{$project}->{"depth"});
	my $branch      = trim($config->{$project}->{"branch"});
	my $git_url	= trim($config->{$project}->{"git_project"});

	my $db_host	= trim($config->{$project}->{"db_host"});
	my $db_port	= trim($config->{$project}->{"db_port"});
	my $db_name	= trim($config->{$project}->{"db_name"});
	my $db_user	= trim($config->{$project}->{"db_user"});
	my $db_pass	= trim($config->{$project}->{"db_pass"});

	my $contact	= trim($config->{$project}->{"contact"});

	my $sysuser	= trim($config->{$project}->{"sysuser"});

	$> = (getpwnam($sysuser))[2];
	$EUID= (getpwnam($sysuser))[2];

	# init the mysql and perm file array
	@mysql_files = ();
	@perm_files = ();

	# Is the project destination path exists ?
        unless (-e $local_path){
		log_this(\@buffer,  "[$project] Your set destination directory does not exists. Create it and rerun the deployment.\n");	
		log_this(\@buffer,  "[$project] Tried local path : $local_path.\n");
                die;
	}

        # Is the project is git initted ?
	my $project_status;
        log_this(\@buffer,  "[$project] No project directory yet\n") if (!opendir(DIR, "$local_path/.git"));
        if (!readdir DIR){
        	# No ! I create it.
		my $git_init_cmd = "$git clone --depth=$depth -b $branch $git_url $local_path";
		mkdir $local_path unless -d $local_path;
        	log_this(\@buffer,  "[$project] Project doesn't exists, creating it...\n");
        	chdir "$local_path";
        	log_this(\@buffer,  "		cd $local_path\n");
		log_this(\@buffer,  "		$git_init_cmd\n");

		$project_status = system($git_init_cmd);
        }
        else {
        	log_this(\@buffer,  "[$project] Project still exists, updating it ...\n");
        	log_this(\@buffer,  "		cd $local_path\n");
        	chdir "$local_path";
        	log_this(\@buffer,  "[$project] Trying to update ...\n");

		# Get the project as its last loaded version (hack to avoid errors generated by changing file permissions)
		my $stash  = `$git stash`;

		# Now, update the project.
		my $status = `$git pull`;
                chomp($status);
                if ($status eq "Already up-to-date."){
        	        log_this(\@buffer,  "[$project] Already up to date.\n");
                }
		
		# project_status takes the return code of the "git pull" command
		$project_status = $?;
	}

	#Project has been loaded or updated, so begin to load sql file and set file perms
	if ($project_status == 0) {
			
		# Update the database
		log_this(\@buffer,  "		Searching for sql file ...");
		find(\&SQLfile, "$local_path");
		log_this(\@buffer,  "No update sql files found\n") if (scalar(@mysql_files) == 0);
			
		foreach my $sql_file (@mysql_files) {
			if (loaddb($db_host, $db_port, $db_name, $db_user, $db_pass, $sql_file) == 0) {
				log_this(\@buffer,  "[$project] SQL file : $sql_file successfully loaded.\n");
				unlink($sql_file);
			}
			else {
				log_this(\@buffer,  "[$project] ERROR : Was unable to load $sql_file.\n");
			}
		}

		# Execute the WordPress script 
		log_this(\@buffer,  "		Searching for WordPress script ...");
		find(\&WPfile, "$local_path");
		log_this(\@buffer,  "No WordPress script found\n") if (scalar(@wp_files) == 0);
			
		foreach my $wp_file (@wp_files) {
			print `$wp_file`;
			unlink($wp_file);
		}

		# Set the file permissions :
		log_this(\@buffer,  "		Searching for permission map file...");
		find(\&PERMfile, "$local_path");
		log_this(\@buffer,  "No permission script found\n") if (scalar(@perm_files) == 0);	

		foreach my $perm_file (@perm_files) {
			set_perm("$local_path/$project", $perm_file);
			unlink($perm_file);
		}

		log_this(\@buffer,  "\n[$project] Project successfully updated\n");
	}
	else {
		log_this(\@buffer,  "\n[$project] Was not able to load the project. See your git config details.\n");
	}

	my @compl = read_file($errors_file);
	print "Sending report to $contact via $smtp for the project $project\n";
	mail_this($smtp, $contact, "", "[Auto Deployment] $project ", \@buffer, \@compl);
		
	# Purge the error file
	close (STDERR);
	unlink($errors_file);
       	
}

sub SQLfile {
        my $file = $File::Find::name;

        if ($file =~ /.*update.*\.sql$/){
                log_this(\@buffer,  "\n		Found SQL update file : $file\n");
		push(@mysql_files, $file);
        }
}

sub PERMfile {
        my $file = $File::Find::name;

        if ($file =~ /\.permission$/){
                log_this(\@buffer,  "\n		Found permission map file : $file\n");
		push(@perm_files, $file);
        }
}

sub WPfile {
        my $file = $File::Find::name;

        if ($file =~ /\.wpactivate$/){
                log_this(\@buffer,  "\n		Found wordpress script : $file\n");
		push(@wp_files, $file);
        }
}

sub loaddb {
        my ($host, $port, $db, $user, $pass, $sql_file) = @_;
	
	return system("$mysql --host=$host -P $port -u $user -p$pass -D $db < $sql_file");
}

sub set_perm {
	my ($path, $perm_file) = @_;

	chdir "$path";

	my @settings = read_file($perm_file);

	# print Dumper(@settings);

	my $file;
	my $owner;
	my $group;
	my $perm_code;
	my $name_uid;

	foreach my $setting (@settings) {

		chomp($setting);
		next if $setting =~ /^#/;

		if ($setting =~ /^(.*),(.*),(.*),(.*)$/){
			$file		= "$path/$1";
			$owner		= $2;
			$group		= $3;
			$perm_code	= $4;

			unless ($name_uid->{$owner}) {
				my ($login,$pass,$uid,$gid) = getpwnam($owner);
				$name_uid->{$owner}->{"uid"} = $uid;
				$name_uid->{$owner}->{"gid"} = $gid;
			} 
			#print "setting $perm_code on $file\n";
			chown $name_uid->{$owner}->{"uid"}, $name_uid->{$owner}->{"gid"}, $file;
			chmod oct($perm_code), $file;
		}
	}
	#unlink($perm_file);
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
        my ($smtp, $recipient, $cc, $title, $body, $complement) = @_;

	my $message = "";

	foreach my $lines (@$body) {
		$message .= $lines;
		# Do not send mais if the project has not been update
		# TODO : make a conf for this.
		return 0 if ($lines =~ /Already up to date/);
	}

	$message .= "\n\nCompléments d'informations :\n";

	foreach my $compl (@$complement) {
		$message .= $compl;
	}

        my $Message = new MIME::Lite (
                From =>'deployment@omegacube.fr',
                To =>$recipient,
                Cc =>$cc,
                Subject =>$title,
                Type =>'TEXT',
                Data =>$message
        );

        $Message -> send("smtp", $smtp);

        return 0;
}

# Just read a file and return it's content into an array
sub read_file {
        my ($file) = @_;

	#print "-\n";
        if(!open(DATA,$file)) {
                die "Unable to open $file : $!\t[ KO ]\n";
        }
        my @lines = <DATA>;
        close(DATA);

        return @lines;
}
