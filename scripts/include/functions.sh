#!/bin/ksh

#---------------------------------------------------------------------------------------------------
# Copyright (c) 2017 Fernando Nunes
# Based on previous script by Frank Ketelaars and Robert Philo
# License: This script is licensed as Apache ( http://www.apache.org/licenses/LICENSE-2.0.html )
# $Author: Fernando Nunes - domusonline@gmail.com $
# $Revision: 1.0.5 $
# $Date 2017-04-24 10:46:12$
# Disclaimer: This software is provided AS IS, without any kind of guarantee. Use at your own risk.
#---------------------------------------------------------------------------------------------------

#---------------------------------------------------------------------------------------------------
# Function to log messages to the designated log file only
#---------------------------------------------------------------------------------------------------
logOnly()
{
	msgType=$1
	msg=$2
	curDate=`date +%Y-%m-%d`
	hostName=`hostname -s`
	timeStamp=`date +"%Y-%m-%d %H:%M:%S"`
	echo $hostName $timeStamp $1 $2 >> ${LOG_DIR}/${PROGNAME}_${curDate}.log
}

#---------------------------------------------------------------------------------------------------
# Logs the message to the designated log file and prints it on stdout
#---------------------------------------------------------------------------------------------------
log()
{
	msgType=$1
	msg=$2
	curDate=`date +%Y-%m-%d`
	hostName=`hostname -s`
	timeStamp=`date +"%Y-%m-%d %H:%M:%S"`
	echo $hostName $timeStamp $1 $2
	echo $hostName $timeStamp $1 $2 >> ${LOG_DIR}/${PROGNAME}_${curDate}.log
}

#---------------------------------------------------------------------------------------------------
# Function to read the output of a command and promote it to
# the designated log file and stdout
#---------------------------------------------------------------------------------------------------
promoteLog()
{
	inputLogFile=$1
	while read line
	do
		if [ "${line}" != "" ]
		then
			log CMDINFO "${line}"
		fi
	done < ${inputLogFile}
}


#---------------------------------------------------------------------------------------------------
# Generate a list of subscriptions for a given instance. Optional 2nd parameter defines the 
# status filter (Running, Idle)
#---------------------------------------------------------------------------------------------------
generate_subs_list()
{
	#Example:
	#Subscription : TEST_ORA
	#Status       : Idle

	l_instance=$1
	if [ $# = 2 ]
	then
		STATUS=$2
	else
		STATUS=Running
	fi

	${CDC_HOME_LOCAL_FS}/bin/dmgetsubscriptionstatus -I ${l_instance} -A | awk -v STATUS=$STATUS '
BEGIN {
        LIST="na"
}
/^Subscription/ {SUB=$NF}
/^Status/ {
if ( ($NF == STATUS) || (STATUS == "ANY" ) )
        if ( LIST == "na" )
        {
                LIST=SUB
        }
        else
        {
                LIST=LIST" "SUB
        }
}
END {
        print LIST
}'
}

#---------------------------------------------------------------------------------------------------
# Obtain the directory of a given instance
#---------------------------------------------------------------------------------------------------
get_instance_dir()
{
	if [ $# != 1 ]
	then
		printf "ERROR: get_instance_dir() called without instance name\n" >&2
		return 1
	else
		if [ "X${CDC_HOME_LOCAL_FS}" = "X" ]
		then
			printf "ERROR: get_instance_dir() called but CDC_HOME_LOCAL_FS is not defined\n" >&2
			return 1
		else
			if [ ! -d ${CDC_HOME_LOCAL_FS} ]
			then
				printf "ERROR: get_instance_dir() called but CDC_HOME_LOCAL_FS (${CDC_HOME_LOCAL_FS}) doesnt look to be a directory\n" >&2
				return 1
			fi
		fi
	fi

	i_INSTANCE=$1
	if [ -r ${CDC_HOME_LOCAL_FS}/conf/userfolder.vmargs ]
	then
		#-Duser.folder="/archivertkprddsa"
		USER_FOLDER=`grep "\-Duser.folder=" ${CDC_HOME_LOCAL_FS}/conf/userfolder.vmargs | cut -f2 -d'"'`
		if [ "X${USER_FOLDER}" = "X" ]
		then
			printf "ERROR: get_instance_dir() - User folder file (${CDC_HOME_LOCAL_FS}/conf/userfolder.vmargs) exists but couldn't get value for user.folder\n" >&2
			return 1
		else
			if [ ! -d ${USER_FOLDER} ]
			then
				printf "ERROR: get_instance_dir() - User folder ($USER_FOLDER) configured doesn't look to be a directory\n" >&2
				return 1
			fi
			if [ ! -d ${USER_FOLDER}/instance/$i_INSTANCE ]
			then
				printf "ERROR: get_instance_dir() - Instance directory (${USER_FOLDER}/instance/$i_INSTANCE) doesn't look to be a directory\n" >&2
				return 1
			else
				echo ${USER_FOLDER}/instance/$i_INSTANCE
				return 0
			fi
		fi
		
	else
		echo ${CDC_HOME_LOCAL_FS}/instance/$i_INSTANCE
		return 0
	fi
}

#---------------------------------------------------------------------------------------------------
# Gets the dmts_trace* file of a given instance
#---------------------------------------------------------------------------------------------------
get_instance_logfile()
{
	if [ $# != 1 ]
	then
		printf "ERROR: get_instance_logfile() was called without an instance name\n"
		return 1
	else
		i_INSTANCE=$1
		i_INSTANCE_DIR=`get_instance_dir $i_INSTANCE`
        	i_FILE=`ls -tr $i_INSTANCE_DIR/log/trace_dmts* | tail -1`

	        if [ ! -r $i_FILE ]
	        then
	                printf "ERROR: get_instance_logfile() - Obtained dmts_trace file (${i_FILE}) cannot be accessed\n" >&2
	                return 1
		else
			echo $i_FILE
			return 0
	        fi
	fi
}

#---------------------------------------------------------------------------------------------------
# Check is a supplied instance is active. Returns 0 if active, 1 if inactive
#---------------------------------------------------------------------------------------------------

instanceIsActive()
{
	a_instance=$1
	${CDC_HOME_LOCAL_FS}/bin/dmshowevents -I $a_instance > /dev/null 2>&1
	if [ $? -le 1 ]
	then
		return 0
	else
		return 1
	fi
}

#---------------------------------------------------------------------------------------------------
# Obtains a list of existing instances
#---------------------------------------------------------------------------------------------------
retrieveDefinedInstances()
{
	l_INSTANCES_COUNT=0
	l_LIST_INSTANCES=""
	for l_instance in `ls ${CDC_INSTANCE_LOCAL_FS}/instance`
	do
		if [ ${l_instance} != "new_instance" ];then
			if [ "X${l_LIST_INSTANCES}" = "X" ]
			then
				l_LIST_INSTANCES=${l_instance}
			else
				l_LIST_INSTANCES="${l_LIST_INSTANCES} ${l_instance}"
			fi
			l_INSTANCES_COUNT=`expr $l_INSTANCES_COUNT + 1`
		fi
	done
	echo $l_LIST_INSTANCES
}


#---------------------------------------------------------------------------------------------------
# Gets an instance alert file. In the instance conf directory there should be a file (user.env)
# with an env variable defined (ALERT_PROP_FILE) which points to the instance alertfile.properties
# which should have a propertie called "file" with the alert file
#---------------------------------------------------------------------------------------------------
get_inst_alert_file()
{
	l_INSTANCE=$1
	l_INST_DIR=`get_instance_dir $l_INSTANCE`
	if [ $? != 0 ]
	then
		logOnly ERROR "get_instance_dir() failed for instance $l_INSTANCE"
		return 1
	else
		if [ ! -f  $l_INST_DIR/conf/user.env ]
		then
			logOnly ERROR "user.env file could not be found (${i_INST_DIR}/conf/user.env) for instance ${l_INSTANCE}"
			return 1
		else
			grep ALERT_PROP_FILE $l_INST_DIR/conf/user.env >/dev/null
			if [ $? != 0 ]
			then
				logOnly ERRROR "user.env does not contain ALER_PROP_FILE definition for instance ${l_INSTANCE}"
				return 1
			else
				ALERT_PROP_FILE=`grep ALERT_PROP_FILE $l_INST_DIR/conf/user.env | cut -f2 -d'='`
				if [ ! -f ${ALERT_PROP_FILE} ]
				then
					logOnly ERROR "Alert Properties file (${ALERT_PROP_FILE}) could not be found for instance ${l_INSTANCE}"
					return 1
				else
					ALERT_FILE=`grep -i -e "^ *file" ${ALERT_PROP_FILE} | cut -f2 -d'='`
					if [ ! -f ${ALERT_FILE}.log ]
					then
						logOnly ERROR "Alert file (${ALERT_FILE}) could not be found for instance ${l_INSTANCE}"
						return 1
					else
						ALERT_SEPARATOR=`grep -i -e "^ *separator" ${ALERT_PROP_FILE} | cut -f2 -d'='`
						echo ${ALERT_FILE}.log ${ALERT_SEPARATOR}
						return 0
					fi
				fi
			fi
		fi
	fi
}



#---------------------------------------------------------------------------------------------------
# Writes a message (3rd parameter) to the instance alert file with the category defined in the
# 2nd parameter. 1st parameter if the instance name
#---------------------------------------------------------------------------------------------------
alert_notification()
{
#2017-04-18 22:01:36|S|RTKS09A|23|Warning|Scrape/Refresh|There are no tables to mirror to the target system. IBM InfoSphere Data Replication will terminate.
	l_INSTANCE=$1
	l_CATEGORY=$2
	l_MESSAGE="$3"
	CURR_DATE=`date +"%Y-%m-%d %H:%M:%S"`
	l_ALERT_DATA=`get_inst_alert_file ${l_INSTANCE}`
	if [ $? != 0 ]
	then
		log ERROR "alert_notification: Error in get_inst_alert_file()"
		return 1
	else
		l_ALERT_FILE=`echo ${l_ALERT_DATA} | cut -f1 -d' '`
		l_ALERT_SEPARATOR=`echo ${l_ALERT_DATA} | cut -f2 -d' '`
		if [ "X${l_ALERT_SEPARATOR}" = "X" ]
		then
			l_ALERT_SEPARATOR="|"
		fi

		echo "${CURR_DATE}${l_ALERT_SEPARATOR}M${l_ALERT_SEPARATOR}0${l_ALERT_SEPARATOR}${l_CATEGORY}${l_ALERT_SEPARATOR}Custom Monitoring${l_ALERT_SEPARATOR}${l_MESSAGE}" >>${l_ALERT_FILE}
	fi
}
