#!/usr/bin/perl 

##########################################################################
#
# Script name : Git Deployer Server
# Author : Guillaume Seigneuret
# Date : 02/01/12
# Type : Deamon
# Description : Receive hook trigger from Git and call the git deployer 
# script
#
# Usage : gds 
#
#
############################################################################

use strict;
use IO::Socket;
use Data::Dumper;

my $ADDRESS 	= "localhost";
my $PORT 	= 32337;

{
	$| = 1;
	my $server = IO::Socket::INET->new(
					LocalHost 	=> $ADDRESS,
					LocalPort	=> $PORT,
					Proto		=> 'tcp',			
					Listen		=> 10 )   # or SOMAXCONN
		or die "Couldn't be a tcp server on port $PORT : $@\n";

	while (my $client = $server->accept()) {
	        unless (my $masterpid = fork() ){
		       	# We are in the child
			#Child doesn't need the listner
			close ($server);
	  		printf "[%12s]", time;
			 
			print " Connection from: ".inet_ntoa($client->peeraddr)."\n";
	  
	  		while(my $rep = <$client>) {
				
				if ( $rep =~ /^QUIT/i) {
					print $client "Bye!\n";
					close($client);
					#print "\n*** Fin de connexion sur PID $$ ***\n";
				} 
				else {
					if($rep =~ /Project: .*\/(\w+.git) Branch: ([\w]+)/) {
						print $client "Recognized Project : $1\r\n";
						print $client "Recognized Branch : $2\r\n";
					}
					else {
						print $client "Query malformed.\r\n";
						close($client);
					}
	    			}
			}
			printf "[%12s]", time; 
			print " Connection closed for ".inet_ntoa($client->peeraddr)." PID $$ \n";
			close($client);
	    		exit 0;
		}
	}
	print "Close Server Called.\n";
	close($server);
}

sub messagePsec {
	my ($time_tracker, $msg_nb, $prev_msg_lenght) = @_;
	
	print "\b" x $prev_msg_lenght;
	my $now = time;
	my $interval = $now - $time_tracker;
	$interval = 1 if ($interval == 0);
	my $answer = int($msg_nb/$interval);
	$answer .= "msg/s";
	
	print $answer;

	return length($answer);

}
