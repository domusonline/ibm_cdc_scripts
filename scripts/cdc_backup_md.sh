#!/bin/ksh
#------------------------------------------------------------------------------
# Copyright (c) 2017 Fernando Nunes
# Based on previous script by Frank Ketelaars and Robert Philo
# License: This script is licensed as Apache ( http://www.apache.org/licenses/LICENSE-2.0.html )
# $Author: Fernando Nunes - domusonline@gmail.com $
# $Revision: 1.0.26 $
# $Date 2017-04-26 16:00:43$
# Disclaimer: This software is provided AS IS, without any kind of guarantee. Use at your own risk.
#------------------------------------------------------------------------------

#------------------------------------------------------------------------------
# Function definitions
#------------------------------------------------------------------------------

#------------------------------------------------------------------------------
# show command syntax
#------------------------------------------------------------------------------

show_help()
{
	echo "${PROGNAME}: -V | -h | "
	echo "               -V shows script version"
	echo "               -h shows this help"
	echo "Ex: ${PROGNAME}"
}

#------------------------------------------------------------------------------
# parse the arguments using standard getopts function
#------------------------------------------------------------------------------

get_args()
{
	arg_ok="Vh"
	while getopts ${arg_ok} OPTION
	do
		case ${OPTION} in
		h)   # show help
			show_help
			exit 0
			;;
		V)      #show version
			echo "${PROGNAME} ${VERSION}" >&1
			exit 0
			;;
		*)
			log ERROR "$$ Invalid parameter (${OPTION}) given"
			return 1
			;;
		esac
	done
}



#------------------------------------------------------------------------------
# clean up...
#------------------------------------------------------------------------------
clean_up()
{
	if [ "X${LIST_TO_BACKUP}" != "X" ]
	then
		for instance in $LIST_TO_BACKUP
		do	
			rm -f ${cmdOut}.$instance
		done
	else
		rm -f ${cmdOut}
	fi
}

#------------------------------------------------------------------------------
# backup an instance's metadata
#------------------------------------------------------------------------------
backupInstance()
{
	${CDC_HOME_LOCAL_FS}/bin/dmbackupmd -I ${instance} >${cmdOut}.$instance 2>&1
	cmdExitCode=$?
	promoteLog ${cmdOut}.$instance
	# If the command was executed successfully, copy the backup to the shared volume
	if [ $cmdExitCode -eq 0 ]
	then
		backupDir=`ls -1rt ${CDC_INSTANCE_LOCAL_FS}/instance/${instance}/conf/backup | tail -1`
		log INFO "Backup executed successfully for instance $instance"
		# Delete old backups from the local volume
		log INFO "Deleting backups for instance ${instance} older than ${CDC_MD_BACKUP_RETENTION_DAYS} days from volume ${CDC_INSTANCE_LOCAL_FS}"
		find ${CDC_INSTANCE_LOCAL_FS}/instance/${instance}/conf/backup/* -mtime +${CDC_MD_BACKUP_RETENTION_DAYS} -print -exec rm -r {} \; > ${cmdOut}.$instance
		promoteLog ${cmdOut}.$instance
	else
		log ERROR "Backup of instance ${instance} did not complete successfully"
	fi
}

# START
PROGNAME=`basename $0`
SCRIPT_DIR=`dirname $0`
VERSION=`echo "$Revision: 1.0.26 $" | cut -f2 -d' '`

NUM_ARGUMENTS=$#
get_args $*
if [ $? != 0 ]
then
        show_help >&2
        log ERROR "$$ Invalid parameters Exiting!"
        exit 1
fi


# Temporary file for command output
cmdOut=/tmp/${PROGNAME}.$$.tmp

# Read the settings from the properties file
if [ -x "${SCRIPT_DIR}/conf/cdc.properties" ]
then
	. "${SCRIPT_DIR}/conf/cdc.properties"
else
	echo "Cannot include properties file ("${SCRIPT_DIR}/conf/cdc.properties"). Exiting!"
	exit 1
fi

# Import general functions
if [ -x  "${SCRIPT_DIR}/include/functions.sh" ]
then
	. "${SCRIPT_DIR}/include/functions.sh"
else
	echo "Cannot include functions file ("${SCRIPT_DIR}/include/functions.sh"). Exiting!"
	exit 1
fi



log INFO "Command $0 executed"
log INFO "SCRIPT DIR = ${SCRIPT_DIR}"
log INFO "Local file system: ${CDC_HOME_LOCAL_FS}"
log INFO "Version: ${VERSION}"

trap clean_up 0

if [ ! -d ${LOG_DIR} ]
then
	log ERROR "Log dir (${LOG_DIR}) does not exist. Exiting!"
	exit 1
else 
	if [ ! -w ${LOG_DIR} ]
	then    
		log ERROR "Log dir (${LOG_DIR}) is not writable. Exiting!"
		exit 1
	fi
fi

INSTANCE_LIST=`retrieveDefinedInstances`
log INFO "Currently defined instances: $INSTANCE_LIST"

LIST_TO_BACKUP=""
if [ "X${CDC_BLACK_LISTED_INSTANCES}" != "X" ]
then
	for instance in $INSTANCE_LIST
	do
		FLAG=0
		for bl_instance in $CDC_BLACK_LISTED_INSTANCES
		do
			#check if instance is black listed
			if [ $instance = $bl_instance ]
			then
				FLAG=1
			fi
		done
		if [ $FLAG = 1 ]
		then
			log INFO "Skipping instance $instance because it's black listed"
		else
			instanceIsActive $instance
			if [ $? = 0 ]
			then
				if [ "X${LIST_TO_BACKUP}" = "X" ]
				then
					LIST_TO_BACKUP=$instance
				else
					LIST_TO_BACKUP="$LIST_TO_BACKUP $instance"
				fi
			else
				log INFO "Skipping instance $instance because it's not active"
			fi
		fi
	done
else
	for instance in $INSTANCE_LIST
	do
		instanceIsActive $instance
		if [ $? = 0 ]
		then
			if [ "X${LIST_TO_BACKUP}" = "X" ]
			then
				LIST_TO_BACKUP=$instance
			else
				LIST_TO_BACKUP="$LIST_TO_BACKUP $instance"
			fi
		else
			log INFO "Skipping instance $instance because it's not active"
		fi
	done
fi

for instance in $LIST_TO_BACKUP
do
	# Run backup against the instance
	log INFO "Running metadata backup for instance ${instance} ..."
	backupInstance $instance &
done

wait
log INFO "Exiting"
