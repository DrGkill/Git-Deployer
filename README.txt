#############################################################################################################
# Script Name:	Git Auto deploy
# Author: 	Guillaume Seigneuret
# Date: 	13.01.2010
# Last mod	23.12.2011
# Version:	0.7
# 
# Usage:	Execute it via crontab or shell prompt, no args
# 
# Usage domain: Works for every web application using MySQL or not.
# 		Also works for basic application without complex dependant environment. 
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
## TODO
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
#
#   Copyright (C) 2011 Guillaume Seigneuret (Omega Cube)
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
#
#############################################################################################################
