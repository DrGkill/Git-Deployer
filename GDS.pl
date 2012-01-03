#!/usr/bin/perl 

##########################################################################
#
# Script name : Git Deployer Server
# Author : 	Guillaume Seigneuret
# Date : 	02/01/12
# Type : 	Deamon
# Version : 	1.0a
# Description : Receive hook trigger from Git and call the git deployer 
# script
#
# Usage : 	gds 
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
my $gitdeployer = "";
our $_PROJECT	= "";

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
						$_PROJECT = $1;

						my $standard_out = select($client);
						# Launch git-deployer
						require $gitdeployer;
						select($standard_out);
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
