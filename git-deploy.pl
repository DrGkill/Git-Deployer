#!/usr/bin/perl
#############################################################################################################
# Script Name:	Git Auto deploy
# Author: 	Guillaume Seigneuret
# Date: 	13.01.2010
# Last mod	07.11.2012
# Version:	1.2.1b
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
use Switch;
use Config::Auto;
use MIME::Lite;
use POSIX qw(setuid);
use File::Find;
use English;
use Data::Dumper;
use Net::SMTP::TLS;
use Net::SMTP::SSL;
use Sys::Hostname;

$| = 1;

our $_PROJECT;
our $_BRANCH;
my $config = Config::Auto::parse();
        #print Dumper($config);

my $debug	= trim($config->{"engine-conf"}->{"debug"});
my $git 	= trim($config->{"engine-conf"}->{"git"});
my $mysql 	= trim($config->{"engine-conf"}->{"mysql"});
my $errors_file = trim($config->{"engine-conf"}->{"error_file"});
my $smtp;
$smtp->{Host}	= trim($config->{"engine-conf"}->{"smtp"});
$smtp->{Sender}	= trim($config->{"engine-conf"}->{"smtp_from"});
(defined $config->{"engine-conf"}->{"smtp_method"}) ? $smtp->{Proto} = trim($config->{"engine-conf"}->{"smtp_method"}) : $smtp->{Proto} = "NONE";
(defined $config->{"engine-conf"}->{"smtp_port"}) ? $smtp->{Port} = trim($config->{"engine-conf"}->{"smtp_port"}) : $smtp->{Port} = 25;
if ($smtp->{Proto} ne "NONE"){
	$smtp->{AuthUser} 	= trim($config->{"engine-conf"}->{"smtp_user"});
	$smtp->{AuthPass}	= trim($config->{"engine-conf"}->{"smtp_pass"});
}

my $hostname = hostname;
my $cyel = "\e[1;33m";
my $cred = "\e[1;31m";
my $cgreen = "\e[1;32m";
my $cend = "\e[0m";

die($cred."Git is not installed$cend\n") unless (-e $git);
print $cyel."WARNING : No MySQL client.$cend\n" unless (-e $mysql);

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
	if (defined $config->{$_PROJECT} and $_PROJECT ne ""
		#	defined trim($config->{$_PROJECT}->{$_BRANCH}) 
	) {
		$project = $_PROJECT;
	}

	if ($project eq ""){
		print $cred."Unable te deploy anything because nor ARGV0 nor \$_PROJECT was set$cend\n.";
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

	
	$EUID = (getpwnam($sysuser))[2];
        $EGID = (getpwnam($sysuser))[3];
	$UID = (getpwnam($sysuser))[2];
        $GID = (getpwnam($sysuser))[3];
	POSIX::setuid((getpwnam($sysuser))[2]);

	$ENV{'HOME'}=(getpwnam($sysuser))[7];
	use lib qw(.);

	# init the mysql and perm file array
	@mysql_files = ();
	@perm_files = ();

	# Is the project destination path exists ?
	print "[".$cgreen.$hostname.$cend."] Updating $project/$branch";
        unless (-e $local_path){
		log_this(\@buffer,  "[".$cgreen.$project.$cend."] $cyel Your set destination directory does not exists.$cend\n",$debug);	
		log_this(\@buffer,  "[".$cgreen.$project.$cend."] Tried local path : $local_path.\n",$debug);
		log_this(\@buffer,  "[".$cgreen.$project.$cend."] I try to create $local_path...",$debug);
		mkdir $local_path unless -d $local_path;
                die $cred." [KO] Wasn't able to create the dir :($cend\n" unless -d $local_path;
		log_this(\@buffer,  "[".$cgreen."OK".$cend."]\n",$debug);
		print ".";
	}

        # Is the project is git initted ?
	my $project_status;
        log_this(\@buffer,  "[$project] No project directory yet\n",$debug) if (!opendir(DIR, "$local_path/.git"));
        if (!readdir DIR){
        	# No ! I create it.
		my $git_init_cmd = "$git clone --depth=$depth -b $branch $git_url $local_path";
	
        	log_this(\@buffer,  "[".$cgreen.$project.$cend."] Project doesn't exists, creating it...\n",$debug);
        	chdir "$local_path";
        	log_this(\@buffer,  "		cd $local_path\n",$debug);
		log_this(\@buffer,  "		$git_init_cmd\n",$debug);

		$project_status = system($git_init_cmd);
		print ".";
        }
        else {
        	log_this(\@buffer,  "[".$cgreen.$project.$cend."] Project still exists, updating it ...\n",$debug);
        	chdir "$local_path";
        	log_this(\@buffer,  "[".$cgreen.$project.$cend."] Trying to update ...\n",$debug);

		# Get the project as its last loaded version (hack to avoid errors generated by changing file permissions)
		my $stash  = `$git stash`;

		# Now, update the project.
		my $status = `$git pull`;
                chomp($status);
                if ($status eq "Already up-to-date."){
        	        log_this(\@buffer,  "[".$cgreen.$project.$cend."] Already up to date.\n",$debug);
                }
		
		# project_status takes the return code of the "git pull" command
		$project_status = $?;
		print ".";
	}

	#Project has been loaded or updated, so begin to load sql file and set file perms
	if ($project_status == 0) {
		$ENV{"PATH"} = "";			
		# Update the database
		print ".";
		log_this(\@buffer,  "		Searching for sql file ...",$debug);
		find({wanted => \&SQLfile, untaint => 1}, "$local_path");
		log_this(\@buffer,  $cyel."No update sql files found$cend\n",$debug) if (scalar(@mysql_files) == 0);
			
		foreach my $sql_file (@mysql_files) {
			if (loaddb($db_host, $db_port, $db_name, $db_user, $db_pass, $sql_file) == 0) {
				log_this(\@buffer,  "[".$cgreen.$project.$cend."] SQL file : $sql_file successfully loaded.\n",$debug);
				unlink($sql_file);
			}
			else {
				log_this(\@buffer,  "[".$cred.$project.$cend."] ERROR : Was unable to load $sql_file.\n",$debug);
			}
		}
		
		# Execute the WordPress script 
		print ".";
		log_this(\@buffer,  "		Searching for WordPress script ...",$debug);
		find({wanted => \&WPfile, untaint => 1}, "$local_path");
		log_this(\@buffer,  $cyel."No WordPress script found$cend\n",$debug) if (scalar(@wp_files) == 0);
			
		foreach my $wp_file (@wp_files) {
			print `$wp_file`;
			unlink($wp_file);
		}

		# Set the file permissions :
		print ".";
		log_this(\@buffer,  "		Searching for permission map file...",$debug);
		find({wanted => \&PERMfile, untaint => 1}, "$local_path");
		log_this(\@buffer,  $cyel."No permission script found$cend\n",$debug) if (scalar(@perm_files) == 0);	

		foreach my $perm_file (@perm_files) {
			set_perm("$local_path/$project", $perm_file);
			unlink($perm_file);
		}

		log_this(\@buffer,  "\n[".$cgreen.$project.$cend."] Project successfully updated\n",$debug);
		print $cgreen."OK".$cend."\n";
	}
	else {
		log_this(\@buffer,  "\n[".$cred.$project.$cend."] Was not able to load the project. See your git config details.\n",$debug);
		print $cred."ERROR".$cend."\n";
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
                log_this(\@buffer,  "\n".$cgreen."		Found SQL update file :$cend $file\n",$debug);
		push(@mysql_files, $file);
        }
}

sub PERMfile {
        my $file = $File::Find::name;

        if ($file =~ /\.permission$/){
                log_this(\@buffer,  "\n".$cgreen."		Found permission map file :$cend $file\n",$debug);
		push(@perm_files, $file);
        }
}

sub WPfile {
        my $file = $File::Find::name;

        if ($file =~ /\.wpactivate$/){
                log_this(\@buffer,  "\n".$cgreen."		Found wordpress script :$cend $file\n",$debug);
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
	print $message if $debug;
	
	# Substitute shell colors before preparing to mail.
	$message =~ s/\e\[\d;\d{2}m//;
	$message =~ s/\e\[0m//;

	push(@$buffer, $message);
	
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
                From => $smtp->{sender},
                To =>$recipient,
                Cc =>$cc,
                Subject =>$title,
                Type =>'TEXT',
                Data =>$message
        );
	
	switch ($smtp->{Proto}) {
		case "NONE"	{ $Message -> send("smtp", $smtp->{Host}, Port=>$smtp->{Port}) }
		case "CLASSIC"	{ 
			$Message -> send("smtp", 
				$smtp->{Host}, 
				Port=>$smtp->{Port}, 
				AuthUser=>$smtp->{AuthUser}, 
				AuthPass=>$smtp->{AuthPass})
		}
		case "TLS"	{ 
			my $mailer = new Net::SMTP::TLS( 
				$smtp->{Host},
				Port    => $smtp->{Port},
				User    => $smtp->{AuthUser},
				Password=> $smtp->{AuthPass});
			$mailer->mail($smtp->{sender});  
			$mailer->to($recipient);  
			$mailer->data;
			$mailer->datasend($Message->as_string);
			$mailer->dataend;  
			$mailer->quit;
		}
		case "SSL"	{
			my $mailer = new Net::SMTP::SSL(
				Port    => $smtp->{Port},
				AuthUser=> $smtp->{AuthUser},
				AuthPass=> $smtp->{AuthPass});
			$mailer->mail($smtp->{sender});  
			$mailer->to($recipient);  
			$mailer->data;
			$mailer->datasend($Message->as_string);
			$mailer->dataend;  
			$mailer->quit;
		}
	}
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
