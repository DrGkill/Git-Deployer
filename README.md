Git-Auto-Deployer - A daemon for auto deploying projects with GIT
=================================================================


![ScreenShot](https://raw.github.com/DrGkill/Git-Deployer/master/diagram.png)
![ScreenShot](https://raw.github.com/DrGkill/Git-Deployer/master/screenshot.png)


Table of Contents:
------------------

* [Introduction] (#intro)
* [Install] (#install)
* [Special scripts] (#ss)


<a name="intro"></a>
### Introduction
Git Auto Deployer help to auto deploy projects on one or multiple servers. 

It has a fonction to set permission on the project, load MySQL, and Word Press scripts. 

It can also manage multiple projects on one server.

This program got a deamon who receive hook trigger from Git and call the git deployer script.

<a name="install"></a>
### Install and Config
The project needs sevral Perl plugins to work properly:

* IO::Socket (installed by default on main systems)
* Config::Auto
* File::Find
* MIME::Lite
* Proc::Daemon
* Net::SMTP::TLS
* Net::SMTP::SSL
* File::LibMagic

To install them : 


```
$ perl -MCPAN -e shell
> install Config::Auto
> install File::Find
> install MIME::Lite
> install Proc::Daemon
> install Net::SMTP::TLS
> install Net::SMTP::SSL
> install File::LibMagic
```

or for Debian :

```
$ apt-get install libmime-lite-perl libconfig-auto-perl libfile-finder-perl libproc-daemon-perl libnet-smtp-tls-perl libnet-smtp-ssl-perl libmagic-dev cpanm
$ cpanm File::LibMagic
```

Clone the project into your favorite directory :

```
$ git clone git://github.com/DrGkill/Git-Deployer.git
```

Place the GDS_start_script in /etc/init.d directory and set it executable :

```
$ cp GDS_start_script /etc/init.d/gds
$ chmod +x /etc/init.d/gds
```

Edit the scipt and make it reflect your configuration :

```
$ vim /etc/init.d/gds
GDS_HOME=/path/where/is/GDS
```


Finally, configure your projects by editing the main configuration file :

Warning, the git-deployer script can be executed either by cron/shell prompt or by the GDS. Depending on that, name the config script by

* GDS.config if lauched by the Git Deployer Server
* git-deployer.config if lauched directly via shell prompt or cron

Begin lines by '#' to make comments

```
$ mv git-deploy.config.sample GDS.config
$ vim GDS.config
# Config file sample for Git-Deployer v1.3
[engine-conf]
	hostname	= MyHostname
	listen		= localhost
	port		= 32337
	pidfile		= /var/run/gds.pid
	logfile		= /var/log/gds.log
	git-deployer	= /home/Git-Deployer/git-deploy.pl
	git 		= /usr/bin/git
	mysql 		= /usr/bin/mysql
	error_file	= /tmp/git-deploy.err
	debug_mode	= off
	smtp		= smtp.example.com
	smtp_from	= sender@example.com
	### SMTP authentication and protocol : NONE|CLASSIC|TLS|SSL, default none
	# smtp_method	= CLASSIC
	# smtp_port	= 465 (default 25)
	# smtp_user	= myusername
	# smtp_pass	= mystrongpassword

    #this can be overriden for each deploy section
    #those right management are not compatible with SetPerm
    protect_elf = on
    protect_ext = php, rb
    ensure_readable = on
    webserver_user = www-data
    

[git-deploy/master]
	depth = 1  
	git_project = git://github.com/DrGkill/Git-Deployer.git
	# Can also work with SSH connection:
	# git_project = git@github.com:DrGkill/Git-Deployer.git

	local_project_path = /home/test
	contact	= deploywatcher@example.com

	db_host = mydatabase
	db_port = 3306
	db_name = gitdeploy
	db_user = gitdeploy
	db_pass = gitdeploy_secret

    git_user = gitdeploy
    git_email = gitdeploy@example.com

	WPscripts = off
	SetPerm = off

	sysuser = git

    #example of override
    webserver_user = apache
    

[end]
```

Launch the server by typing:

```
$ service gds start
Starting Git Deployment Server ... [STARTED]
```

The script provides you the ability to <code>stop</code>, <code>start</code> and <code>restart</code> the daemon.

To finish you may want to make it start with your server :

```
$ runlevel
N2
$ cd /etc/rc.2/; ln -s ../init.d/gds S30gds
```


<a name="ss"></a>
### Special Scripts

Git Deployer is able to launch scripts after having pulled a project.
You can specify a MySQL script file, WordPress script file and/or a permission mapping file.

To enable search for MySQL script file, you have to define a database in the project config section.
So need at least db_host to be set.
Then push in your project a file ending with ".sqlupdate". File will be executed with the system user defined in the project config section and deleted after execution.

To enable search for WordPress script file (WPcli), you have to set "WPscripts = on" into the concerned project config section.
Then push in your project a file ending with ".wpactivate". File will be executed with the system user defined in the project config section and deleted after execution.

To enable search for permission mapping file, you have to set "SetPerm = on" into the concerned project config section.
Then push in your project a file ending with ".permission". File will be executed with the system user defined in the project config section and deleted after execution.
The mapping file has to be generated with the map_perm.pl tool contained into the project.
