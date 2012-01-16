#!/usr/bin/perl 

##########################################################################
#
# Script name : Git Deployer Server
# Author : 	Guillaume Seigneuret
# Date : 	16/01/12
# Type : 	Deamon
# Version : 	1.0b
# Description : Receive hook trigger from Git and call the git deployer 
# script
#
# Usage : 	gds <pidfile>
# 		Fill the ADDRESS, PORT and gitdeployer variables as
# 		wanted.
#
##   Copyright (C) 2012 Guillaume Seigneuret (Omega Cube)
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
############################################################################

use strict;
use IO::Socket;
use Data::Dumper;

my $ADDRESS 	= "localhost";
my $PORT 	= 32337;
my $gitdeployer = "/home/git-deployer/git-deploy.pl";

{
	$| = 1;

	our $_PROJECT   = "";
	our $_BRANCH	= "";

	if (defined($ARGV[0])){
		my $PID_file = $ARGV[0] ;
		die "A git deployment server is already running\n" if(-e $PID_file);
		die "Unable to open $PID_file for writing" unless open (PIDf,">$PID_file");
		print PIDf $$;
		close(PIDf);
	}

	my $server = IO::Socket::INET->new(
					LocalHost 	=> $ADDRESS,
					LocalPort	=> $PORT,
					Proto		=> 'tcp',			
					Listen		=> 10 )   # or SOMAXCONN
		or die "Couldn't be a tcp server on port $PORT : $@\n";

	print "GDS started, waiting for connections...\n";
	
	while (my $client = $server->accept()) {
	        unless (my $masterpid = fork() ){
		       	# We are in the child
			#Child doesn't need the listner
			close ($server);
	  		printf "[%12s]", time;
			 
			print " Connection from: ".inet_ntoa($client->peeraddr)."\n";
	  		print $client "Welcome on GDS, please make your request.\r\n";

	  		while(my $rep = <$client>) {
			
				printf "[%12s] Asked to interpret : %s", time, $rep;

				if ( $rep =~ /^QUIT/i) {
					print $client "Bye!\n";
					close($client);
					#print "\n*** Fin de connexion sur PID $$ ***\n";
				} 
				else {
					if($rep =~ /Project: .*\/([\w\-\.]+)\.git Branch: ([\w\-]+)/) {
						print $client "Recognized Project : $1\r\n";
						print $client "Recognized Branch : $2\r\n";
						$_PROJECT 	= $1;
						$_BRANCH	= $2;

						# Send the STDout to the client.
						my $standard_out = select($client);
						# Launch git-deployer
						print "Launching Git Deployer...\n";
						require "$gitdeployer";
						
						# restore the stdout
						select($standard_out);
						close($client);
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
