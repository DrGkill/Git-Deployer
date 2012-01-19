Git-Auto-Deployer - A daemon for auto deploying projects with GIT
=================================================================

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

To install them : 


```
$ perl -MCPAN -e shell
> install Config::Auto
> install File::Find
> install MIME::Lite
> install Proc::Daemon
```

or for Debian :

```
$ apt-get install libmime-lite-perl libconfig-auto-perl libfile-finder-perl libproc-daemon-perl
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
[engine-conf]
	## Only for GDS
	listen		= localhost
	port		= 32337
	pidfile		= /var/run/gds.pid
	logfile		= /var/log/gds.log
	##

	## For Git-deployer
	git 		= /usr/bin/git
	mysql 		= /usr/bin/mysql
	error_file	= /tmp/git-deploy.err
	smtp		= smtp.example.com

[git-deploy]
	branch = master
	depth = 1
	user = git
	server = github.com
	git_project = git-deploy/git-deploy.git

	local_project_path = /home/test
	contact	= deploywatcher@example.com

	db_host = mydatabase
	db_port = 3306
	db_name = gitdeploy
	db_user = gitdeploy
	db_pass = gitdeploy_secret

	sysuser = git

[end]
```

<a name="ss"></a>
### Special Scripts

To be documented.
