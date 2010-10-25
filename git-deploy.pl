#!/usr/bin/perl

# git archive --format=zip --remote git@git.netemedia.fr:git-deploy/git-deploy.git master -o git-deploy.zip
# Git deploy should :
#       [OK] Get the directory and script/http files into a specific directory
#       - Be able to set file/directory permissions
#       - Be able to look after a sql file and update the database
#       - Be able to verify the application environment (Web server config, php, ruby, python config)
#       [OK] Search for new versions

use strict;
use Config::Auto;
use DBD::mysql;
use File::Find;
use Data::Dumper;

my $git = "/usr/bin/git";

{
        my $config = Config::Auto::parse();
        #print Dumper($config);

        foreach my $project (keys(%$config)) {

                my $local_path  = trim($config->{$project}->{local_project_path});
                my $depth       = trim($config->{$project}->{depth});
                my $branch      = trim($config->{$project}->{branch});
                my $user        = trim($config->{$project}->{user});
                my $server      = trim($config->{$project}->{server});
                my $git_project = trim($config->{$project}->{git_project});

                # Is destination path exists ?
                unless (-e $local_path){
                        print "No such file or directory : .$local_path.\n";
                        next;
                }

                # Is the project exists ?
                print "Failed while opening $local_path\n" if (!opendir(DIR, "$local_path/$project/.git"));
                if (!readdir DIR){
                        # No ! I create it.
                        print "Project doesn't exists, creating it...\n";
                        chdir "$local_path";
                        print "cd $local_path\n";
                        print "$git clone --depth=$depth -b $branch $user\@$server:$git_project\n";
                        #print `pwd`;
                        if( system("$git clone --depth=$depth -b $branch $user\@$server:$git_project\n") == 0){
                                print "Project successfully loaded\n";
                                # The project is successfully loaded, I search for a database and I load it.
                                print "Searching for sql file ...\n";
                                find(\&SQLload, "$local_path/$project");
                        }

                }
                else {
                        print "Project still exists, updating it ...\n";
                        print "cd $local_path\n";
                        chdir "$local_path/$project";
                        print "Trying to update ...\n";
                        my $status = `$git pull`;
                        chomp($status);
                        if ($status ne "Already up-to-date."){
                                find(\&SQLload, "$local_path/$project");
                        }
                        else {
                                print "Already up to date.\n";
                        }
                }
        }
}

sub SQLload {
        my $file = $File::Find::name;
        if ($file =~ /\.sql$/){
                print "Found $file !!! Youhoo !\n";
        }
        #else {
        #       print "This is no sql file :( :$file\n";
        #}
}

sub loaddb {
        my ($host, $port, $db, $user, $pass, $sql_file) = @_;
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

