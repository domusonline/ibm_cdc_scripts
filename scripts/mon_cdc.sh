#!/bin/ksh
# Copyright (c) 2017 Fernando Nunes - fernando.nunes@pt.ibm.com
# Based on previous script by Frank Ketelaars and Robert Philo
# License: This script is licensed as Apache ( http://www.apache.org/licenses/LICENSE-2.0.html )
# $Author: Fernando Nunes - domusonline@gmail.com $
# $Revision: 1.0.2 $
# $Date 2017-04-19 23:18:15$
# Disclaimer: This software is provided AS IS, without any kind of guarantee. Use at your own risk.

#------------------------------------------------------------------------------
# Function definitions
#------------------------------------------------------------------------------

alert_mail()
{
	BODY=$1
	${SENDMAIL} ${SENDMAIL_OPTIONS} <<EOF
FROM: $ALARM_FROM
TO: $ALARM_TO
CC: $ALARM_CC
SUBJECT: $ALARM_SUBJECT
----------------------------------------------------------
$BODY
----------------------------------------------------------
.
EOF

}

check_instance_running()
{
	RUN_INSTANCE_NAME=$1
		
	CURR_DATE=`date +"%Y-%m-%d %H:%M:%S"`
	NEW_PID=dummy
	ps -ef | grep dmts64 | grep "${RUN_INSTANCE_NAME}$" | awk 'BEGIN {PID="dummy"} {if ( $3 == 1 ) {PID=$2}} END {print PID}' | read NEW_PID
	if [ $NEW_PID = "dummy" ]
	then
		#--------------------------------------------------------------------------------------
		# instance is not running
		#--------------------------------------------------------------------------------------
		if [ -r ${TMP_DIR}/.${PROGNAME}_alarm_count_${RUN_INSTANCE_NAME} ]
		then
			cat ${TMP_DIR}/.${PROGNAME}_alarm_count_${RUN_INSTANCE_NAME} | read ALARM_COUNT
		else
			ALARM_COUNT=0
		fi
		ALARM_COUNT=`expr $ALARM_COUNT + 1`
		echo $ALARM_COUNT > ${TMP_DIR}/.${PROGNAME}alarm_count_${RUN_INSTANCE_NAME}
		log INFO "CDC instance $RUN_INSTANCE_NAME is not running! Alarm count: $ALARM_COUNT"
		alert_notification $RUN_INSTANCE_NAME "Fatal" "CDC instance $RUN_INSTANCE_NAME is not running!"
		if [ $ALARM_COUNT -le $ALARM_COUNT_LIMIT ]
		then
			alert_mail "$CURR_DATE CDC instance ${RUN_INSTANCE_NAME} is not running! ALARM COUNT: $ALARM_COUNT"
		fi
		echo 0 > ${TMP_DIR}/.${PROGNAME}_instance_pid_${RUN_INSTANCE_NAME}
	else
		if [ -r ${TMP_DIR}/.${PROGNAME}_instance_pid_${RUN_INSTANCE_NAME} ]
		then
			cat ${TMP_DIR}/.${PROGNAME}_instance_pid_${RUN_INSTANCE_NAME} | read OLD_PID
		else
			OLD_PID=0
		fi
		if [ $OLD_PID != $NEW_PID ]
		then
			if [ $OLD_PID = 0 ]
			then
				alert_notification $RUN_INSTANCE_NAME "Warning" "CDC instance ${RUN_INSTANCE_NAME} was started! PID: $NEW_PID"
				alert_mail "CDC instance ${RUN_INSTANCE_NAME} was started! PID: $NEW_PID"
				log INFO "CDC instance ${RUN_INSTANCE_NAME} was started! PID: $NEW_PID"
			else
				alert_notification $RUN_INSTANCE_NAME "Warning" "CDC instance ${RUN_INSTANCE_NAME} was restarted! PID: $NEW_PID"
				alert_mail "$CURR_DATE CDC instance ${RUN_INSTANCE_NAME} was restarted! PID: $NEW_PID"
				log INFO "CDC instance ${RUN_INSTANCE_NAME} was restarted! PID: $NEW_PID"
			fi
		else
			log INFO "CDC instance ${RUN_INSTANCE_NAME} is running. PID: ${NEW_PID}"
		fi
		echo $NEW_PID > ${TMP_DIR}/.${PROGNAME}_instance_pid_${RUN_INSTANCE_NAME}
		echo 0 > ${TMP_DIR}/.${PROGNAME}_alarm_count_${RUN_INSTANCE_NAME}
	fi
}

#------------------------------------------------------------------------------
# START of the script. Above are function definitions
#------------------------------------------------------------------------------

PROGNAME=`basename $0`
SCRIPT_DIR=`dirname $0`
TMP_DIR=${SCRIPT_DIR}/tmp
VERSION=`echo "$Revision: 1.0.2 $" | cut -f2 -d' '`

# Read the settings from the properties file
if [ -x $SCRIPT_DIR/conf/cdc.properties ]
then
 	. $SCRIPT_DIR/conf/cdc.properties
else
	echo "Cannot include properties file ($SCRIPT_DIR/conf/cdc.properties). Exiting!"
	exit 1
fi

# Import general functions
if [ -x  "$SCRIPT_DIR/include/functions.sh" ]
then
	. "$SCRIPT_DIR/include/functions.sh"
else
	echo "Cannot include functions file ($SCRIPT_DIR/include/functions.sh). Exiting!"
	exit 1
fi


if [ ! -d ${LOG_DIR} ]
then
	log ERROR "Log dir (${LOG_DIR}) does not exist"
	exit 1
else
	if [ ! -w ${LOG_DIR} ]
	then
		log ERROR "Log dir (${LOG_DIR}) is not writable"
		exit 1
	fi
fi

if [ ! -d ${TMP_DIR} ]
then
	log ERROR "TMP dir (${TMP_DIR}) does not exist"
	exit 1
else
	if [ ! -w ${TMP_DIR} ]
	then
		log ERROR "TMP dir (${TMP_DIR}) is not writable"
		exit 1
	fi
fi


ALARM_COUNT=0



log INFO "Command ${PROGNAME} executed"
log INFO "SCRIPT DIR = ${SCRIPT_DIR}"
log INFO "Local file system: ${CDC_HOME_LOCAL_FS}"
log INFO "Version: ${VERSION}"

INSTANCE_LIST=`retrieveDefinedInstances`
log INFO "Currently defined instances: $INSTANCE_LIST"


for INST in $INSTANCE_LIST
do
	if [ "X${CDC_BLACK_LISTED_INSTANCES}" != "X" ]
	then
		FLAG=0
		for bl_instance in $CDC_BLACK_LISTED_INSTANCES
		do
			#check if instance is black listed
			if [ $INST = $bl_instance ]
			then
				FLAG=1
			fi
		done
		if [ $FLAG = 1 ]
		then
			log INFO "Skipping instance $instance because it's black listed"
                else
			log INFO "Checking instance ${INST}"
			check_instance_running $INST
		fi
	else
		log INFO "Checking instance ${INST}"
		check_instance_running $INST
	fi
done
log INFO "Exiting"
