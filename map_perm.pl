#!/usr/bin/perl

use strict;
use File::Find;

my $perm_file = "project.permission";
my $root_project = $ARGV[0];

{
	print "#file,owner,group,permission\n";
	find(\&stat_file, $root_project);
	
}

sub stat_file {
        my $file = $File::Find::name;
	
	return 0 if $file =~ /\.git/;

	my @stats = stat($file);

	$file =~ s/$root_project/./;

	my $uid 	= (getpwuid($stats[4]))[0];
	my $gid 	= (getgrgid($stats[5]))[0];
	my $mode 	= $stats[2];

	#my @pwd 	= getpwuid($uid);
	#my $username	= $pwd[1];

	#printf "UID: %s, GID: %s, MODE: %04o  -  %s\n",$uid,$gid,$mode & 07777,$file;
	printf "%s,%s,%s,%04o\n",$file,$uid,$gid,$mode & 07777;
}
