#!/usr/bin/perl
#############################################################################################################
# Script Name:	Git Auto deploy
# Author: 	Guillaume Seigneuret
# Date: 	13.01.2010
# Last mod	27.06.2013
# Version:	1.3.14
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
use warnings;

use Switch;
use Config::Auto;
use MIME::Lite;
use POSIX qw(setuid);
use File::Find;
use English;
use Data::Dumper;
use Net::SMTP::TLS;
use Net::SMTP::SSL;
use Term::ANSIColor qw(:constants);
use IO::Handle;
use File::LibMagic;

my @IGNORED_FILES = ('/\.git$', '/\.git/', '/\.$', '/\.\.$');

$| = 1;

our $_PROJECT;
our $_BRANCH;
local $Term::ANSIColor::AUTORESET = 1;

my $_log_progress__previous_display = undef;
my $_log_progress__wheel_status = 0;
my $_log_progress__wheel_chars = "-\\|/";

my $OUTHANDLER;

my $config = Config::Auto::parse();
        #print Dumper($config);
my $git 	= trimperso($config->{"engine-conf"}->{"git"});
my $mysql 	= trimperso($config->{"engine-conf"}->{"mysql"});
my $errors_file = trimperso($config->{"engine-conf"}->{"error_file"});
my $hostname	= trimperso($config->{"engine-conf"}->{"hostname"});
my $smtp = ();
$smtp->{Host}	= trimperso($config->{"engine-conf"}->{"smtp"});
$smtp->{Sender}	= trimperso($config->{"engine-conf"}->{"smtp_from"});

if (defined $config->{"engine-conf"}->{"smtp_method"}) {
	$smtp->{Proto} = trimperso($config->{"engine-conf"}->{"smtp_method"})
}
else {
	$smtp->{Proto} = "NONE";
}

if (defined $config->{"engine-conf"}->{"smtp_port"}) {
	$smtp->{Port} = trimperso($config->{"engine-conf"}->{"smtp_port"})
}
else {
	$smtp->{Port} = 25;
}

if ($smtp->{Proto} ne "NONE"){
	$smtp->{AuthUser} 	= trimperso($config->{"engine-conf"}->{"smtp_user"});
	$smtp->{AuthPass}	= trimperso($config->{"engine-conf"}->{"smtp_pass"});
}


my $default_protect_elf = $config->{"engine-conf"}->{"protect_elf"};
$default_protect_elf = 0 unless defined $default_protect_elf;
$default_protect_elf = lc(trimperso($default_protect_elf));
$default_protect_elf = "on" if ($default_protect_elf =~ /1|on|true/);

my $default_protect_ext_str = $config->{"engine-conf"}->{"protect_ext"};
my @default_protect_ext = ();
@default_protect_ext = map({ trimperso($_) } split(/,/, $default_protect_ext_str)) if $default_protect_ext_str;

my $default_ensure_readable = $config->{"engine-conf"}->{"ensure_readable"};
$default_ensure_readable = 0 unless defined $default_ensure_readable;
$default_ensure_readable = lc(trimperso($default_ensure_readable));
$default_ensure_readable = "on" if ($default_ensure_readable =~ /1|on|true/);

my $default_webserver_user = $config->{"engine-conf"}->{"webserver_user"};
$default_webserver_user = trimperso($default_webserver_user) if defined $default_webserver_user;

my $default_wpscript = $config->{"engine-conf"}->{"WPscripts"};
$default_wpscript = trimperso($default_webserver_user) if defined $default_wpscript;

my $default_setperm = $config->{"engine-conf"}->{"SetPerm"};
$default_setperm = trimperso($default_setperm) if defined $default_setperm;

my $magic = File::LibMagic->new();

print BOLD RED "[$hostname]: Git is not installed !!!\n" unless (-e $git);
die("Git is not installed\n") unless (-e $git);
print BOLD YELLOW "WARNING : No MySQL client.\n" unless (-e $mysql);

# Create a buffer for logging message during the script execution.
my @buffer = ();
# Create a global array for the sql file because of this *** find function
my @mysql_files = ();
my @perm_files = ();
my @wp_files = ();

{
	# Redirect STDERR to a buffer.
	open (STDERR,">$errors_file");
    $OUTHANDLER = select;
	my $project = "";

	# Initializing "project" variable via shell args.
	$project = $ARGV[0]."/".$ARGV[1] if(defined $ARGV[0] and defined $ARGV[1] and defined trimperso($config->{$ARGV[0]."/".$ARGV[1]}) );	

	# Initializing "project" variable via GDS.
	if (defined $config->{"$_PROJECT/$_BRANCH"}
	) {
		$project = "$_PROJECT/$_BRANCH";
	}

	if ($project eq ""){
		print BOLD GREEN "[$hostname]: ";
		print BOLD RED "Unable to deploy anything because the project was not passed in argument OR not defined in the deployer server config file\n. Hint : ./git-deploy project-name branch\n";
		die "Unable to deploy anything because the project was not passed in argument OR not defined in the deployer server config file\n.";
	}

	# Loading the project settings
	my $local_path  = trimperso($config->{$project}->{"local_project_path"});
	my $depth       = trimperso($config->{$project}->{"depth"});
	my $branch      = $_BRANCH;
	my $git_url	= trimperso($config->{$project}->{"git_project"});

	my $db_host	= trimperso($config->{$project}->{"db_host"});
	my $db_port	= trimperso($config->{$project}->{"db_port"});
	my $db_name	= trimperso($config->{$project}->{"db_name"});
	my $db_user	= trimperso($config->{$project}->{"db_user"});
	my $db_pass	= trimperso($config->{$project}->{"db_pass"});

	my $contact	= trimperso($config->{$project}->{"contact"});

    my $git_user = trimperso($config->{$project}->{"git_user"});
    my $git_email = trimperso($config->{$project}->{"git_email"});

	my $sysuser	= trimperso($config->{$project}->{"sysuser"});
	
	my $reset_hard = 0;
	$reset_hard = trimperso($config->{$project}->{"reset_hard"}) if defined $config->{$project}->{"reset_hard"};

    my $protect_elf = $config->{$project}->{"protect_elf"};
    $protect_elf = $default_protect_elf unless defined $protect_elf;
    $protect_elf = 0 unless defined $protect_elf;
    $protect_elf = lc(trimperso($protect_elf));
    $protect_elf = ($protect_elf =~ /1|on|true/);

    my $protect_ext_str = $config->{$project}->{"protect_ext"};
    my @protect_ext = @default_protect_ext;
    @protect_ext = map({ trimperso($_) } split(/,/, $protect_ext_str)) if $protect_ext_str;

    my $ensure_readable = $config->{$project}->{"ensure_readable"};
    $ensure_readable = $default_ensure_readable unless defined $ensure_readable;
    $ensure_readable = 0 unless defined $ensure_readable;
    $ensure_readable = lc(trimperso($ensure_readable));
    $ensure_readable = ($ensure_readable =~ /1|on|true/);

    my $webserver_user = $config->{$project}->{"webserver_user"};
    $webserver_user = $default_webserver_user unless defined $webserver_user;
    $webserver_user = trimperso($webserver_user) if defined $webserver_user;

	if ($local_path eq ""){
		print BOLD GREEN "[$hostname]: ";
		print BOLD RED "Project path was not defined in the config file... Exiting\n";
		die "Project path was not defined in the config file... Exiting\n";
	}
	
	# If I'm root, then i'll be able to switch the user
	# Else i'll not be able to, and maybe I don't need it.
	if ( $UID == 0) {
        $EGID = (getpwnam($sysuser))[3];
        $GID = (getpwnam($sysuser))[3];
        POSIX::setgid((getpwnam($sysuser))[3]);

        $EUID = (getpwnam($sysuser))[2];
        $UID = (getpwnam($sysuser))[2];
        POSIX::setuid((getpwnam($sysuser))[2]);
        
        $ENV{'HOME'}=(getpwnam($sysuser))[7];
        use lib qw(.);
	}

	# init the mysql and perm file array
	@mysql_files = ();
	@perm_files = ();

	# Is the project destination path exists ?
	unless (-e $local_path){
		log_this(\@buffer,  "Your set destination directory does not exists.\n",$project,"warning");	
		log_this(\@buffer,  "Tried local path : $local_path.\n",$project,"warning");
		log_this(\@buffer,  "Trying to create $local_path...",$project,"warning");
		mkdir $local_path unless -d $local_path;
		unless (-d $local_path) {
			log_this(\@buffer,  "Wasn't able to create the dir :(\n","","ko");
			die " [KO] Wasn't able to create the dir :(\n" unless -d $local_path;
		}
		log_this(\@buffer,  " OK.\n","","ok");
	}

        # Is the project is git initted ?
	my $project_status;
    log_this(\@buffer,  "No project directory yet\n",$project,"warning") if (!opendir(DIR, "$local_path/.git"));
    if((not -e "$local_path/.git") or (not -d "$local_path/.git") or (!readdir DIR)){
        # No ! I create it.
        my $git_init_cmd = "$git clone --depth=$depth -b $branch $git_url $local_path";

        log_this(\@buffer,  "Project doesn't exists, creating it...\n",$project,"warning");
        chdir "$local_path";
        # TODO ADD DEBUG MODE
        log_this(\@buffer,  "		cd $local_path\n",$project,"ok");
        log_this(\@buffer,  "		$git_init_cmd\n",$project,"ok");

        $project_status = system($git_init_cmd);

        if($project_status == 0) {
            if($git_user) {
                my $git_user_cmd = "$git config user.name \"$git_user\"";
                system($git_user_cmd) == 0 and log_this(\@buffer,  "		$git_user_cmd\n",$project,"ok");
            }
            if($git_email) {
                my $git_email_cmd = "$git config user.name \"$git_email\"";
                system($git_email_cmd) == 0 and log_this(\@buffer,  "		$git_email_cmd\n",$project,"ok");
            }
        }
    }
    else {
        log_this(\@buffer,  "Project found, updating it ...\n",$project,"ok");
        chdir "$local_path";
        #log_this(\@buffer,  "[$project] Trying to update ...\n");

        # Do this silently (aka no log), 'cause it should already have been done
        if($git_user) {
            my $git_user_cmd = "$git config user.name \"$git_user\"";
            system($git_user_cmd);
        }
        if($git_email) {
            my $git_email_cmd = "$git config user.name \"$git_email\"";
            system($git_email_cmd);
        }
        
        my $checkout = qx{$git checkout $branch};

        # Get the project as its last loaded version (hack to avoid errors generated by potential local changes)
        my $stash  = qx{$git stash};
		
		my $reset_status;
		$reset_status = qx{git reset --hard origin/$branch} if $reset_hard;

        # Now, update the project.
        my $status = qx{$git pull origin $branch};
        chomp($status);
        if ($status eq "Already up-to-date."){
            log_this(\@buffer,  "Already up to date.\n",$project,"ok");
            exit 0;
        }

        # project_status takes the return code of the "git pull" command
        $project_status = $?;
    }

	#Project has been loaded or updated, so begin to load sql file and set file perms
	if ($project_status == 0) {
		$ENV{"PATH"} = "";			
		# Update the database*
		if (defined $config->{$project}->{"db_host"}) {
			log_this(\@buffer,  "		Searching for sql file ...",$project,"warning");
			find({wanted => \&SQLfile, untaint => 1}, "$local_path");
			log_this(\@buffer,  "No update sql files found\n",$project,"ko") if (scalar(@mysql_files) == 0);
			
			foreach my $sql_file (@mysql_files) {
				if (loaddb($db_host, $db_port, $db_name, $db_user, $db_pass, $sql_file) == 0) {
					log_this(\@buffer,  "SQL file : $sql_file successfully loaded.\n",$project,"ok");
					unlink($sql_file);
				}
				else {
					log_this(\@buffer,  "ERROR : Was unable to load $sql_file.\n",$project,"ko");
				}
			}
		}

		$config->{$project}->{"WPscripts"} = $default_wpscript
			if not defined $config->{$project}->{"WPscripts"};
		if (is_on($config->{$project}->{"WPscripts"})) {
			# Execute the WordPress script 
			log_this(\@buffer,  "		Searching for WordPress script ...");
			find({wanted => \&WPfile, untaint => 1}, "$local_path");
			log_this(\@buffer,  "No WordPress script found\n",$project,"ko") if (scalar(@wp_files) == 0);
			
			foreach my $wp_file (@wp_files) {
				print qx{$wp_file};
				unlink($wp_file);
			}
		}

        my $perm_file_found = 0;
		$config->{$project}->{"SetPerm"} = $default_setperm
			if not defined $config->{$project}->{"SetPerm"};
		if (is_on($config->{$project}->{"SetPerm"})) {
			# Set the file permissions :
			log_this(\@buffer,  "		Searching for permission map file...");
			find({wanted => \&PERMfile, untaint => 1}, "$local_path");
			log_this(\@buffer,  "No permission script found\n",$project,"ko") if (scalar(@perm_files) == 0);	

            $perm_file_found = (scalar(@perm_files) > 0);
			foreach my $perm_file (@perm_files) {
				set_perm("$local_path/$project", $perm_file);
				unlink($perm_file);
			}
		}

        if(!$perm_file_found) {
            my @group_ids;
            @group_ids = get_group_ids($webserver_user) if $webserver_user;
            
            if($ensure_readable) {
                qx{/bin/chmod -R ug+X "$local_path"};
                qx{/bin/chmod -R u+r "$local_path"};
                if($webserver_user){
                    my @unreadable = get_unreadable($local_path, @group_ids);
                    for my $file (@unreadable) {
                        qx{/bin/chmod g+r "$file"};
                        log_progress(\@buffer, "Ensure readability", "Add group read permission on $file\n",$project,"ok");
                    }
                    @unreadable = get_unreadable($local_path, @group_ids);
                    for my $file (@unreadable) {
                        qx{/bin/chmod o+r "$file"};
                        qx{/bin/chmod o+x "$file"} if -d $file;
                        log_progress(\@buffer, "Ensure readability", "Add guest read permission on $file\n",$project,"ok");
                    }
                }                
            }

            find({wanted => sub {
                    my $file = $File::Find::name;
                    for my $pattern (@IGNORED_FILES) {
                        return if $file =~ /$pattern/;
                    }
                    if(should_be_protected($file, $protect_elf, @protect_ext)) {
                        if(-d $file){
                            qx{/bin/chmod o-w "$file"};
                            log_progress(\@buffer, "Protecting files", "Remove guest write permissions on folder $file\n",$project,"ok");
                        }
                        else {
                            qx{/bin/chmod o-wx "$file"};
                            log_progress(\@buffer, "Protecting files", "Remove guest write and execute permissions on file $file\n",$project,"ok");
                        }
                    }                    
                }, untaint => 1},
                $local_path);

            if($webserver_user){
                my @writable = get_writable($local_path, @group_ids);
                for my $file (@writable) {
                    if(should_be_protected($file, $protect_elf, @protect_ext)) {
                        qx{/bin/chmod g-w "$file"};
                        log_progress(\@buffer, "protecting files", "Remove group write permissions on $file\n",$project,"ok");
                    }
                }
            }
        }
		log_this(\@buffer,  "Project successfully updated\n",$project,"ok");
	}
	else {
		log_this(\@buffer,  "Was not able to load or update the project. See git details.\n",$project,"ko");
		print read_file($errors_file) if -e $errors_file;
	}

	my @compl = read_file($errors_file);

	print "More informations: ";
	foreach my $comp (@compl) {
		print $comp;
	}

	if ($contact ne "") {
		print "Sending report to $contact via ".$smtp->{Host}." for the project $project\n";
		mail_this($smtp, $contact, "", "[Auto Deployment] $project on $hostname", \@buffer, \@compl);
	}
	
	# Purge the error file
	close (STDERR);
	unlink($errors_file);
       	
}

sub SQLfile {
        my $file = $File::Find::name;

        if ($file =~ /.*update.*\.sql$/){
                log_this(\@buffer,  "\n		Found SQL update file : $file\n","","ok");
		push(@mysql_files, $file);
        }
}

sub PERMfile {
        my $file = $File::Find::name;

        if ($file =~ /\.permission$/){
                log_this(\@buffer,  "\n		Found permission map file : $file\n","","ok");
		push(@perm_files, $file);
        }
}

sub WPfile {
        my $file = $File::Find::name;

        if ($file =~ /\.wpactivate$/){
                log_this(\@buffer,  "\n		Found wordpress script : $file\n","","ok");
		push(@wp_files, $file);
        }
}

sub get_group_ids {
    my $user = shift;

    my $user_id;
    my $user_name;
    if($user =~ /^\d+$/) {
        $user_id = $user;
        $user_name = getpwuid($user);
    }
    else {
        $user_id = getpwnam($user);
        $user_name = $user;
    }

    my $main_gid;
    my @groups = ();

    while (my ($name, $pass, $uid, $gid, $quota, $comment, $gcos, $dir, $shell, $expire) = getpwent()) {
        if(($name eq $user_name) and ($uid == $user_id)) {
            $main_gid = $gid;
        }
    }

    while (my ($name, $passwd, $gid, $members) = getgrent()) {
        if(defined($main_gid) && ($gid == $main_gid)){
            push(@groups, $gid);
            next;
        }
        next unless $members;
        my @memberlist = map({ trimperso($_) } split(/\s+/, $members));
        if(@memberlist and grep(/^\Q$user_name\E$/, @memberlist)) {
            push(@groups, $gid);
        }
    }
    return @groups;
}

sub get_writable {
    my $folder = shift;
    my @groups = @_;

    my @writable_files = ();
    find({wanted => sub {
            my $file = $File::Find::name;
            for my $pattern (@IGNORED_FILES) {
                return if $file =~ /$pattern/;
            }
            my @file_stats = stat($file);
            my $group_id = $file_stats[5];
            my $mode = ($file_stats[2]+0) & 07777;
            push(@writable_files, $file) if ($mode & POSIX::S_IWGRP) and grep(/^\Q$group_id\E$/, @groups);
        }, untaint => 1},
        $folder);

    return @writable_files;
}

sub get_unreadable {
    my $folder = shift;
    my @groups = @_;

    my @unreadable_files = ();
    find({wanted => sub {
            my $file = $File::Find::name;
            for my $pattern (@IGNORED_FILES) {
                return if $file =~ /$pattern/;
            }   
            
            my @file_stats = stat($file);
            my $group_id = $file_stats[5];
            my $mode = ($file_stats[2]+0) & 07777 ;
            my $readable = ($mode & POSIX::S_IROTH);
            $readable = 1 if ($mode & POSIX::S_IRGRP) and grep(/^\Q$group_id\E$/, @groups) and not $readable;
            if((-d $file) and ($readable)){
                $readable = ($mode & POSIX::S_IXOTH);
                $readable = 1 if ($mode & POSIX::S_IXGRP) and grep(/^\Q$group_id\E$/, @groups) and not $readable;
            }
            push(@unreadable_files, $file) unless $readable;
        }, untaint => 1},
        $folder);

    return @unreadable_files;
}

sub should_be_protected {
    my $file = shift;
    my $protect_elf = shift;
    my @protect_ext = @_;

    if($protect_elf and $magic->info_from_filename($file)->{description} =~ /executable/) {
        return 1;
    }
    for my $ext (@protect_ext) {
        return 1 if $file =~ /\.\Q$ext\E$/;
    }
    return 0;
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


sub log_progress {
    my ($buffer, $display, $message, $project, $status) = @_;
    push(@$buffer, $message);

    if(defined($_log_progress__previous_display) and $display eq $_log_progress__previous_display) {
        $_log_progress__wheel_status = ($_log_progress__wheel_status +1 ) % 4;
        print "\b";
        print substr($_log_progress__wheel_chars, $_log_progress__wheel_status, 1);
        print "\n" if $OUTHANDLER ne \*STDOUT;
        $OUTHANDLER->flush();
    }
    else {
        print "\n" if defined($_log_progress__previous_display);
        $_log_progress__previous_display = $display;
        $_log_progress__wheel_status = 0;
        dislay_msg($display." ", $project, $status);
        print substr($_log_progress__wheel_chars, $_log_progress__wheel_status, 1);
        $OUTHANDLER->flush();
    }
}

sub log_this {
	my ($buffer, $message, $project, $status) = @_;
	push(@$buffer, $message);

    if(defined($_log_progress__previous_display)) {
        $_log_progress__previous_display = undef;
        print "\n";
    }
    dislay_msg($message, $project, $status);
}

sub dislay_msg {
    my ($message, $project, $status) = @_;
    
	my $decorator = "";
	$decorator = "[".$project." @ ".$hostname."]: " if $project ne "";

	if ($status eq "ok") {
		print BOLD GREEN $decorator;
		print BOLD WHITE $message;
	}
	if ($status eq "warning") {
		print BOLD GREEN $decorator;
		print BOLD YELLOW $message;
	}
	if ($status eq "ko") {
		print BOLD GREEN $decorator;
		print BOLD RED $message;
	}
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

	$message .= "\n\nMore informations :\n";

	foreach my $compl (@$complement) {
		$message .= $compl;
	}

        my $Message = new MIME::Lite (
                From => $smtp->{Sender},
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
				AuthPass=>$smtp->{AuthPass}) || die "SASL Authentication failed\n";
		}
		case "TLS"	{ 
			my $mailer = new Net::SMTP::TLS( 
				$smtp->{Host},
				Hello   => $smtp->{Sender},
				Port    => $smtp->{Port},
				User    => $smtp->{AuthUser},
				Password=> $smtp->{AuthPass})
			|| die "SASL authentication failed via TLS\n";
			$mailer->mail($smtp->{sender});  
			$mailer->to($recipient);  
			$mailer->data;
			$mailer->datasend($Message->as_string);
			$mailer->dataend;  
			$mailer->quit;
		}
		case "SSL"	{
			my $mailer = new Net::SMTP::SSL(
				$smtp->{Host},
				Hello   => $smtp->{Sender},
				Port    => $smtp->{Port},
				AuthUser=> $smtp->{AuthUser},
				AuthPass=> $smtp->{AuthPass})
			|| die "SASL authentication failed via SSL\n";
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

sub trimperso
{
    my @out = @_;
    for (@out)
    {
		next if not defined $_;
        s/^\s+//;
        s/\s+$//;
    }
    return wantarray ? @out : $out[0];
}

sub is_on {
        my $input = shift;
        my $default = shift;
        $default = 0 unless defined($default);

        return 0 unless defined($input);
        return 1 if $input =~ /on|ok|1|y|yes|true/i;
        return 0 if $input =~ /off|0|no|false/i;
        return $default;
}

1;

