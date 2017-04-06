#!/bin/ksh
# Copyright (c) 2017 Fernando Nunes - fernando.nunes@pt.ibm.com
# Based on previous script by Frank Ketelaars and Robert Philo
# License: This script is licensed as Apache ( http://www.apache.org/licenses/LICENSE-2.0.html )
# $Author: Fernando Nunes - domusonline@gmail.com $
# $Revision: 1.0.1 $
# $Date 2017-04-06 15:28:45$
# Disclaimer: This software is provided AS IS, without any kind of guarantee. Use at your own risk.

#------------------------------------------------------------------------------
# Function definitions
#------------------------------------------------------------------------------

#------------------------------------------------------------------------------
# show command syntax
#------------------------------------------------------------------------------

show_help()
{
	echo "${PROGNAME}: -V | -h | [-c] [-t] [-r] [-I {INST1[,INST2...]}] [-m {Y|N} | -M {Y|N|F}] {start | stop | status | clean}"
	echo "               -V shows script version"
	echo "               -h shows this help"
	echo "               -I defines list of comma separated instance names"
	echo "               -c cleans staging store"
	echo "               -r restores latest metadatab backup"
	echo "               -t clean transaction queues"
	echo "               -m Y starts subscriptions on start"
	echo "               -m N don't start subscriptions on start"
	echo "               -M Y stops subscriptions in controlled manner on stop"
	echo "               -M N don't stop subscriptions on stop"
	echo "               -M F stops subscriptions in controlled manner and later with immediate"
	echo "Ex: ${PROGNAME} -r -c -t -I INSTSRC01,INSTSRC02 start"
}

#------------------------------------------------------------------------------
# parse the arguments using standard getopts function
#------------------------------------------------------------------------------

get_args()
{
	arg_ok="VhctrI:m:M:"
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
                I)   # set up the -i instances list
			INSTANCES_FLAG=1
			INSTANCES=$OPTARG
			echo ${INSTANCES} | egrep "^[a-zA-Z][a-zA-Z0-9\-_]*(,[a-zA-Z][a-zA-Z0-9\-_])*" 1>/dev/null 2>/dev/null
			RES=$?
			if [ "X${RES}" != "X0" ]
			then
				echo "${PROGNAME}: Syntax error - Instances list must be valid instance names separated by commas" >&2
				return 1
			fi
                        ;;
                c)   # set up the -c clean staging store
			CLEAN_STAGING_STORE_FLAG=1
			;;
                r)   # set up the -r restore metadata flag
			RESTORE_MD_FLAG=1
			;;
                t)   # set up the -t clean transaction queues
			CLEAN_TXN_QUEUES_FLAG=1
			;;
                m)   # set up the -m start mirroring
			START_MIRRORING_OPT=$OPTARG
			case $START_MIRRORING_OPT in
			y|Y)
				START_MIRRORING_FLAG=1
				;;
			n|N)
				START_MIRRORING_FLAG=0
				;;
			*)
				echo "${PROGNAME}: Syntax error - Invalid start mirroring option ($START_MIRRORING_OPT)" >&2
				return 1	
				;;
			esac
			;;
                M)   # set up the -m start mirroring
			STOP_MIRRORING_OPT=$OPTARG
			case $STOP_MIRRORING_OPT in
			f|F)
				STOP_MIRRORING_FLAG=2
				;;
			y|Y)
				STOP_MIRRORING_FLAG=1
				;;
			n|N)
				STOP_MIRRORING_FLAG=0
				;;
			*)
				echo "${PROGNAME}: Syntax error - Invalid stop mirroring option ($STOP_MIRRORING_OPT)" >&2
				return 1	
				;;
			esac
		esac
	done
	if [ ${NUM_ARGUMENTS} -ge ${OPTIND} ]
	then
		shift `expr $OPTIND - 1`
		if [ $# -gt 1 ]
		then
			echo "${PROGNAME}: Syntax error: Too many parameters" >&2
			show_help >&2
			return 2
		else
			ACTION=$1
			case $ACTION in
			start|stop|status|clean)
				echo "Parameter ok" >/dev/null
				;;
			*)
				echo "${PROGNAME}: Syntax error: Invalid action parameter" >&2
				return 2
				;;
			esac
		fi
	else
		echo "${PROGNAME}: Syntax error: Too few parameters" >&2
		show_help >&2
		return 2
	fi
		
}


#------------------------------------------------------------------------------
# Try to stop the subscriptions in "normal" way.
# Returns 0 if successful, 1 if some remain active
#------------------------------------------------------------------------------

stop_subs()
{

	l_instance=$1
	${CDC_HOME_LOCAL_FS}/bin/dmendreplication -I ${l_instance} -A -c >$cmdOut 2>&1
	promoteLog $cmdOut

	#start waiting loop

	LOOP_ITERACTION=1

	RC=1
	while [ ${LOOP_ITERACTION} -le ${CDC_LOOP_LIMIT} ]
	do	
		L_SUBS_RUN_LIST=`generate_subs_list ${l_instance}`
		if [ "X${L_SUBS_RUN_LIST}" = "Xna" ]
		then
			log INFO "All subscriptions for instance ${l_instance} are stopped"
			RC=0
			break
		else
			log INFO "There are still running subscriptions (${L_SUBS_RUN_LIST}) for instance ${l_instance}. Keep waiting (${CDC_LOOP_INTERVAL}s loop ${LOOP_ITERACTION} from ${CDC_LOOP_LIMIT})"
			sleep $CDC_LOOP_INTERVAL &
			wait
		fi
		LOOP_ITERACTION=`expr $LOOP_ITERACTION + 1`
	done
	return $RC
}

#------------------------------------------------------------------------------
# Retrieves all instances if -i was not supplied or verifies if the supplied
# list exist. LIST_INSTANCES will contain the valid list and INSTANCE_COUNT
# the number considered/found
#------------------------------------------------------------------------------

retrieveInstances()
{
	log INFO "Retrieving CDC instances"
	INSTANCES_COUNT=0
	if [ "X$INSTANCES_FLAG" = "X" ]
	then
		for instance in `ls ${CDC_INSTANCE_LOCAL_FS}/instance`
		do
			if [ ${instance} != "new_instance" ];then
				log INFO "Instance found: ${instance}"
				if [ "X${LIST_INSTANCES}" = "X" ]
				then
					LIST_INSTANCES=${instance}
				else
					LIST_INSTANCES="${LIST_INSTANCES} ${instance}"
				fi
				INSTANCES_COUNT=`expr $INSTANCES_COUNT + 1`
			fi
		done
	else
		LIST_INSTANCES=""
		for instance in `echo $INSTANCES | sed 's/,/ /g'`
		do
			if [ -d ${CDC_INSTANCE_LOCAL_FS}/instance/$instance ]
			then
				if [ "X${LIST_INSTANCES}" = "X" ]
				then
					LIST_INSTANCES=${instance}
				else
					LIST_INSTANCES="${LIST_INSTANCES} ${instance}"
				fi
				INSTANCES_COUNT=`expr $INSTANCES_COUNT + 1`
			else
				log WARNING "Specified instance $instance does not exist. Skipping."
			fi
		done
		if [ $INSTANCES_COUNT -gt 0 ]
		then
			log INFO "Working with the following instance(s): $LIST_INSTANCES"
		else
			log ERROR "List of valid instances is empty. Exiting!"
			exit 1
		fi
	fi
}

#------------------------------------------------------------------------------
# Check is a supplied instance is active
# Returns 0 if active, 1 if inactive
#------------------------------------------------------------------------------

instanceActive()
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

#------------------------------------------------------------------------------
# Restores the latest version of the metadata created by cdc_backup.sh script
# The metadata backup images are stored in the INSTANCE_DIR/conf/backup/bN
# directory, "N" being a sequential number
#------------------------------------------------------------------------------

restoreMetadata()
{
	instance=$1
	backupDir=`ls -1rt ${CDC_INSTANCE_LOCAL_FS}/instance/${instance}/conf/backup | tail -1`
	if [ -d ${CDC_INSTANCE_LOCAL_FS}/instance/${instance}/conf/backup/${backupDir} ]
	then
		log INFO "Restoring latest version of the metadata, ${backupDir}, for instance ${instance}"
		cp -p ${CDC_INSTANCE_LOCAL_FS}/instance/${instance}/conf/backup/${backupDir}/* ${CDC_INSTANCE_LOCAL_FS}/instance/${instance}/conf/ > $cmdOut 2>&1
		RC=$?
		promoteLog $cmdOut
		return $RC
	else
		log WARNING "Backup DIR ($backupDir) does not exist or is not available for instance $instance"
		return 1
	fi
}

#------------------------------------------------------------------------------
# Calls the cleaning of the staging store
# The instance must be running
#------------------------------------------------------------------------------

cleanStagingStore()
{
	instance=$1
	instanceActive $instance
	if [ $? = 0 ]
	then
		log INFO "Clearing staging store for instance $instance"
		${CDC_HOME_LOCAL_FS}/bin/dmclearstagingstore -I $instance > $cmdOut 2>&1
		RC=$?
		promoteLog $cmdOut
	else
		log ERROR "Clearing staging store attempted for an instance ($instance) that is not active"
		RC=1
	fi
	return $RC
}

#------------------------------------------------------------------------------
# Removes the transaction queue files from INSTANCE_DIR/txnstore
#------------------------------------------------------------------------------

cleanTxnQueues()
{
	instance=$1
	log INFO "Clearing transaction queues for instance $instance"
	FILE_COUNT=`ls ${CDC_INSTANCE_LOCAL_FS}/instance/${instance}/txnstore/ | wc -l`
	if [ $FILE_COUNT -gt 0 ]
	then
		rm ${CDC_INSTANCE_LOCAL_FS}/instance/${instance}/txnstore/* >$cmdOut 2>&1
		RC=$?
		promoteLog $cmdOut
	else
		log INFO "Transaction queues directory for instance $instance is empty"
		RC=0
	fi
	return $RC
}

#------------------------------------------------------------------------------
# Manages the backup (cdc_backup.sh) process for the specified instance
# Receives the instance name and the action (start/stop)
# Validates consistency between the running process and the PID file
#------------------------------------------------------------------------------

BackupProcess()
{
	instance=$1
	backupAction=$2

	if [ ! -r  ${SCRIPT_DIR}/pid/cdc_backup_md_${instance}.pid ]
	then    
		#Backup file does not exist
		RUN_PID=`ps -ef | grep -v grep | egrep "cdc_backup_md.sh ${instance}$" | awk 'BEGIN {RUNNING=0} {RUNNING=1;PID=$2} END {print RUNNING " " PID}'`
		RUNNING=`echo $RUN_PID | cut -f1 -d' '`
		backupPID=`echo $RUN_PID | cut -f2 -d' '`
		if [ $RUNNING != 0 ]
		then
			#backup process exist
			case $backupAction in
			start)
				log WARNING "Metadata backup process for instance ${instance} was running with PID ${backupPID} but the PID file didn't exist. Creating the file"
				echo ${backupPID} > ${SCRIPT_DIR}/pid/cdc_backup_md_${instance}.pid
				;;
			stop)
				log WARNING "Metadata backup process for instance ${instance} was running with PID ${backupPID} but the PID file didn't exist. Stoping the process"
				kill -15 $backupPID
				;;
			*)
				log ERROR "Invalid action ($backupAction) in BackupProcess function: Exiting"
				exit 1
			esac
		else
			#Metadata backup process did not exist
			case $backupAction in
			start)
				nohup ${SCRIPT_DIR}/cdc_backup_md.sh ${instance} > /dev/null 2>&1 &
				backupPID=$!
				echo ${backupPID} > ${SCRIPT_DIR}/pid/cdc_backup_md_${instance}.pid
				log INFO "Metadata backup process for instance $instance started in background with PID ${backupPID}"
				;;
			stop)
				log INFO "Metadata backup process for instance $instance was already stopped"
				;;
			*)
				log ERROR "Invalid action ($backupAction) in BackupProcess function: Exiting"
				exit 1
				;;
			esac
		fi
	else
		backupPID=$(cat ${SCRIPT_DIR}/pid/cdc_backup_md_${instance}.pid)
		RUNNING=`ps -fp ${backupPID} | grep -v grep | egrep "cdc_backup_md.sh ${instance}$" | wc -l`
		if [ $RUNNING = 1 ]
		then
			case $backupAction in
			start)
				log INFO "Metadata backup process for instance ${instance} is already running (${backupPID})"
				;;
			stop)
				log INFO "Metadata backup process for instance ${instance} was running with PID ${backupPID}."
				log INFO "Stopping the process and cleaning the file"
				kill -15 $backupPID
				rm -f ${SCRIPT_DIR}/pid/cdc_backup_md_${instance}.pid
				;;
			*)
				log ERROR "Invalid action ($backupAction) in BackupProcess function: Exiting"
				exit 1
			esac
		else
			case $backupAction in
			start)
				log INFO "Metadata backup process PID file (${backupPID}) existed but process was not running"
				nohup ${SCRIPT_DIR}/cdc_backup_md.sh ${instance} > /dev/null 2>&1 &
				backupPID=$!
				echo ${backupPID} > ${SCRIPT_DIR}/pid/cdc_backup_md_${instance}.pid
				log INFO "Metadata backup process started in background with PID ${backupPID}"
				;;
			stop)
				log INFO "Metadata backup PID file for instance ${instance} existed but process was not running. Removing the file"
				rm -f ${SCRIPT_DIR}/pid/cdc_backup_md_${instance}.pid
				;;
			*)
				log ERROR "Invalid action ($backupAction) in BackupProcess function: Exiting"
				exit 1
				;;
			esac
		fi
	fi
}

#------------------------------------------------------------------------------
# Starts all the specified instances
# Depending on -t, -r and -c flags it can clear the txn queues, restore the
# metadata and clean the staging store
#------------------------------------------------------------------------------

# Start all instances
startInstances()
{
	returnCode=0
	log INFO "Starting all specified instances"
	instancesActive=0
	LIST_SUCCESSFUL=""
	LIST_UNSUCCESSFUL=""
	LIST_INDOUBT=""
	for instance in ${LIST_INSTANCES}
	do
		rm -f $cmdOut
		instanceActive $instance
		if [ $? != 0 ]
		then
			if [ $CLEAN_TXN_QUEUES_FLAG = 1 ]
			then
				cleanTxnQueues $instance
			fi
			if [ $RESTORE_MD_FLAG = 1 ]
			then
				restoreMetadata $instance
			else
				#If abnormal flag file exists instance has not been properly closed down  
				if [ -f $SCRIPT_DIR/${instance}_started ]
				then
					log WARNING "Instance $instance previously ended abnormally. Ensure the instance is working correctly"
				fi
			fi
		else
			if [ ! -f $SCRIPT_DIR/${instance}_started ]
			then
				touch $SCRIPT_DIR/${instance}_started
				log INFO "Instance $instance was already active but flag file didn't exist. Created"
			else
				log INFO "Instance $instance was already active"
				continue
			fi
		fi
		log INFO "Starting instance ${instance} ..."
		nohup ${CDC_HOME_LOCAL_FS}/bin/dmts64 -I ${instance} > $cmdOut 2>&1 &
		
		START_WAIT_LIMIT=180
		START_TIME=0
		START_WAIT_INTERVAL=15
		START_TIMEOUT_FLAG=1
		while [ $START_TIME -lt $START_WAIT_LIMIT ]
		do
			if [ ! -s $cmdOut ]
			then
				sleep $START_WAIT_INTERVAL
			else
				START_TIMEOUT_FLAG=0
				grep "IBM InfoSphere Data Replication is running" $cmdOut >/dev/null
				if [ $? = 0 ]
				then
					LIST_SUCCESSFUL="${LIST_SUCCESSFUL}$instance "
					touch $SCRIPT_DIR/${instance}_started
					instancesActive=`expr $instancesActive + 1`
					promoteLog $cmdOut
					if [ $CLEAN_STAGING_STORE_FLAG = 1 ]
					then
						cleanStagingStore $instance
					fi
					break
				else
					LIST_UNSUCCESSFUL="${LIST_UNSUCCESSFUL}$instance "
					log ERROR "Instance $instance did not start successfully"
					promoteLog $cmdOut
				fi
			fi
		done
		if [ $START_TIMEOUT_FLAG = 1 ]
		then
			LIST_INDOUBT="${LIST_INDOUBT}$instance "
			log WARNING "Instance $instance failed to start in the specified number of seconds ($START_WAIT_LIMIT)"
			log EARNING "Please verify status for instance $instance"
		fi
	done

	if [ $instancesActive -ne ${INSTANCES_COUNT} ]
	then
		log WARNING "Not all instances were started"
		log WARNING "Successfuly started: $LIST_SUCCESSFUL"
		log WARNING "Not started: $LIST_UNSUCCESSFUL"
		log WARNING "In doubt: $LIST_INDOUBT"
		returnCode=1
	else
		log INFO "All instances started successfuly"
	fi
	
	return $returnCode
}

#------------------------------------------------------------------------------
# Stops all instances
#------------------------------------------------------------------------------

stopInstances()
{
	for instance in ${LIST_INSTANCES}
	do
		instanceActive $instance
		if [ $? = 0 ]
		then
			log INFO "Stopping instance ${instance}"
			${CDC_HOME_LOCAL_FS}/bin/dmshutdown -I ${instance} > $cmdOut 2>&1 &
			result=$?
			if [ $result -eq 0 ]
			then
				LOOP_ITERACTION=1
				RC=1
				while [ ${LOOP_ITERACTION} -le ${CDC_LOOP_LIMIT} ]
				do	
					instanceActive ${instance}
					if [ $? != 0 ]
					then
						#Instance is already stopped
						RC=0
						break
					else
						#Instance is still running. Keep waiting
						sleep $CDC_LOOP_INTERVAL &
						wait
					fi
					LOOP_ITERACTION=`expr $LOOP_ITERACTION + 1`
				done
				if [ $RC = 0 ]
				then
					log INFO "Instance ${instance} shut down successfully. Clearing flag"
					rm -f $SCRIPT_DIR/${instance}_started
				else
					log WARNING "Instance ${instance} failed to shut down successfully"
				fi
			else
				log WARNING "Instance ${instance} failed to shut down successfully with error code $result"
			fi
			promoteLog $cmdOut
		else
			if [ -f $SCRIPT_DIR/${instance}_started ]
			then
				rm -f $SCRIPT_DIR/${instance}_started
				log WARNING "Instance $instance was already stoped but flag file existed"
			else
				log WARNING "Instance $instance was already stoped"
			fi
		fi
	done
  
	# The following is commented as it's not clear if it's a desirable action
	# Wait a few seconds, then terminate instances if no intances were provided in the command line
	#if [ "X${INSTANCES_FLAG}" = "X0" ]
	#then
	#	sleep 5
	#	terminateInstances
	#	log INFO "Would call terminateInstances"
	#fi
}

#------------------------------------------------------------------------------
# Terminates all instances. Currently is not being used
#------------------------------------------------------------------------------

terminateInstances()
{
	log INFO "Terminating all CDC instances"
	${CDC_HOME_LOCAL_FS}/bin/dmterminate &> $cmdOut
	promoteLog $cmdOut
}

#------------------------------------------------------------------------------
# Starts the specified instances and optionally (-m) their subscriptions
#------------------------------------------------------------------------------

start()
{
	startInstances
	# Now start all subscriptions in all instances
	if [ "X${START_MIRRORING_FLAG}" = "XY" ]
	then
		for instance in ${LIST_INSTANCES}
		do
			log INFO "Starting subscriptions for instance ${instance} ..."
			${CDC_HOME_LOCAL_FS}/bin/dmstartmirror -I ${instance} -A > $cmdOut
			promoteLog $cmdOut
		done
	fi
	
	for instance in ${LIST_INSTANCES}
	do
		BackupProcess $instance start
	done
}

#------------------------------------------------------------------------------
# Stops all specified subscriptions, stops the backup process
# -M controls if we attempt to stop the subscriptions
#------------------------------------------------------------------------------

stopFunc()
{
	for s_instance in ${LIST_INSTANCES}
	do
		# Stop the backup background process and remove the PID file
		BackupProcess $s_instance stop
	done

	if [ ${STOP_MIRRORING_FLAG} = "Y" -o ${STOP_MIRRORING_FLAG} = "F" ]
	then
		# Stop all subscriptions controlled
		for s_instance in ${LIST_INSTANCES}
		do
			log INFO "Stopping subscriptions controlled for instance ${s_instance}"
			instanceActive $s_instance
			if [ $? != 0 ]
			then
				log WARNING "Cannot stop instance $s_instance subscriptions because the instance is not active"
			else
				stop_subs ${s_instance}
			fi
		done

		# Now stop subscriptions immediately if -M flag was specified with "F" option
		if [ "X$STOP_MIRRORING_FLAG" = "XF" ]
		then
			for s_instance in ${LIST_INSTANCES}
			do
				log INFO "Stopping subscriptions immediately for instance ${s_instance}"
				instanceActive $s_instance
				if [ $? = 0 ]
				then
					${CDC_HOME_LOCAL_FS}/bin/dmendreplication -I ${s_instance} -A -i &> $cmdOut
					promoteLog $cmdOut
				fi
			done
		fi
	fi

	# Wait again, then stop and eventually terminate instances
	sleep 10
	stopInstances
}

#------------------------------------------------------------------------------
# Shows the status of instances and it's subscriptions
#------------------------------------------------------------------------------

status() {
	instancesActive=0
	for instance in ${LIST_INSTANCES}
	do
		instanceActive $instance
		if [ $? = 0 ]
		then
			log INFO "Instance ${instance} is active"
			instancesActive=`expr $instancesActive + 1`
			${CDC_HOME_LOCAL_FS}/bin/dmgetsubscriptionstatus -I ${instance} -A >$cmdOut 
			promoteLog $cmdOut
		else
			log INFO "Instance ${instance} is inactive"
		fi
	done
	log INFO "Number of CDC instances that are active: ${instancesActive}. Number of CDC instances checked: ${INSTANCES_COUNT}"
}

#------------------------------------------------------------------------------
# Action used with options -c, -t and -r
#------------------------------------------------------------------------------

clean()
{
	for instance in $LIST_INSTANCES
	do
		RC_TXN_QUEUES=0
		RC_MD=0
		RC_STAGING_STORE=0
		if [ $CLEAN_TXN_QUEUES_FLAG = 1 ]
		then
			cleanTxnQueues $instance
			RC_TXN_QUEUES=$?
		fi

		if [ $RESTORE_MD_FLAG = 1 ]
		then
			restoreMetadata $instance
			RC_MD=$?
		fi
		if [ $CLEAN_STAGING_STORE_FLAG = 1 ]
		then
			cleanStagingStore $instance
			RC_STAGING_STORE=$?
		fi
		if [ $RC_TXN_QUEUES = 0 -a $RC_MD = 0 -a $RC_STAGING_STORE = 0 ]
		then
			log INFO "All clean here!"
		else
			if [ $RC_STAGING_STORE != 0 ]
			then
				STAGING_STORE_MSG="Clean of staging store failed."
			fi
			if [ $RC_MD != 0 ]
			then
				MD_MSG="Restore of Metadata failed."
			fi
			if [ $RC_TXN_QUEUES != 0 ]
			then
				QUEUES_MSG="Clean of tansaction queues failed."
			fi
			RC_MSG="Not all actions succeeded for instance $instance: $STAGING_STORE_MSG $MD_MSG $QUEUES_MSG"
			log WARNING "$RC_MSG"
		fi
	done
}

clean_up()
{
	rm -f $cmdOut
}

#------------------------------------------------------------------------------
# START of the script. Above are function definitions
#------------------------------------------------------------------------------

PROGNAME=`basename $0`
SCRIPT_DIR=`dirname $0`
VERSION=`echo "$Revision: 1.0.1 $" | cut -f2 -d' '`
export MYUSER=`id -u -n`
LOGUID=`id -u`
cmdOut=/tmp/$PROGNAME.$$.tmp
trap clean_up 0

# Ensure the script is not started as root
if [ ${LOGUID} = 0 ]
then
	echo "Script cannot be run as root user. Please run it as the owner of the CDC installation" >&2
	exit 1
fi


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

NUM_ARGUMENTS=$#
get_args $*
if [ $? != 0 ]
then
	show_help >&2
	exit 1
fi


#------------------------------------------------------------------------------
# Verify argument consistency and sets defaults
#------------------------------------------------------------------------------

case ${ACTION} in
start)
	if [ "X${CLEAN_STAGING_STORE_FLAG}" = "X" ]
	then
		if [ "X${CLEAN_STAGING_STORE_DEFAULT}" != "X" ]
		then
			CLEAN_STAGING_STORE_FLAG=$CLEAN_STAGING_STORE_DEFAULT
		else
			CLEAN_STAGING_STORE_FLAG=0
		fi
	fi
	if [ "X${CLEAN_TXN_QUEUES_FLAG}" = "X" ]
	then
		if [ "X${CLEAN_TXN_QUEUES_DEFAULT}" != "X" ]
		then
			CLEAN_TXN_QUEUES_FLAG=$CLEAN_TXN_QUEUES_FLAG_DEFAULT
		else
			CLEAN_TXN_QUEUES_FLAG=0
		fi
	fi
	if [ "X${RESTORE_MD_FLAG}" = "X" ]
	then
		if [ "X${RESTORE_MD_DEFAULT}" != "X" ]
		then
			RESTORE_MD_FLAG=$RESTORE_MD_DEFAULT
		else
			RESTORE_MD_FLAG=0
		fi
	fi
	case "X"$START_MIRRORING_FLAG in
	X)
		if [ "X${START_MIRRORING_DEFAULT}" != "X" ]
		then
			START_MIRRORING_FLAG=$START_MIRRORING_DEFAULT
		else
			START_MIRRORING_FLAG=Y
		fi
		;;
	X1)
		START_MIRRORING_FLAG=Y
		;;
	X0)
		START_MIRRORING_FLAG=N
		;;
	esac
	if [ "X${STOP_MIRRORING_FLAG}" != "X" ]
	then
		echo "${PROGNAME}: Syntax error: Option -M cannot be specified with action 'start'"
		exit 1
	fi
	;;
stop)
	case "X"$STOP_MIRRORING_FLAG in
	X)
		if [ "X${STOP_MIRRORING_DEFAULT}" != "X" ]
		then
			STOP_MIRRORING_FLAG=$STOP_MIRRORING_DEFAULT
		else
			STOP_MIRRORING_FLAG=Y
		fi
		;;
	X0)
		STOP_MIRRORING_FLAG="N"
		;;
	X1)
		STOP_MIRRORING_FLAG="Y"
		;;
	X2)
		STOP_MIRRORING_FLAG="F"
		;;
	esac
	if [ "X${START_MIRRORING_FLAG}" != "X" ]
	then
		echo "${PROGNAME}: Syntax error: Option -m cannot be specified with action 'stop'"
		exit 1
	fi
	;;
status)
	if [ "X${CLEAN_STAGING_STORE_FLAG}" != "X" -o "X${RESTORE_MD_FLAG}" != "X" -o "X${CLEAN_TXN_QUEUES_FLAG}" != "X" -o "X${START_MIRRORING_FLAG}" != "X" -o "X${STOP_MIRRORING_FLAG}" != "X" ]
	then
		echo "${PROGNAME}: Syntax error: Options -c, -t, -r, -m and -M cannot be specified with action 'status'"
		exit 1
	fi
	;;
clean)
	if [ "X${CLEAN_STAGING_STORE_FLAG}" = "X" ]
	then
		if [ "X${CLEAN_STAGING_STORE_DEFAULT}" != "X" ]
		then
			CLEAN_STAGING_STORE_FLAG=$CLEAN_STAGING_STORE_DEFAULT
		else
			CLEAN_STAGING_STORE_FLAG=0
		fi
	fi
	if [ "X${CLEAN_TXN_QUEUES_FLAG}" = "X" ]
	then
		if [ "X${CLEAN_TXN_QUEUES_DEFAULT}" != "X" ]
		then
			CLEAN_TXN_QUEUES_FLAG=$CLEAN_TXN_QUEUES_FLAG_DEFAULT
		else
			CLEAN_TXN_QUEUES_FLAG=0
		fi
	fi
	if [ "X${RESTORE_MD_FLAG}" = "X" ]
	then
		if [ "X${RESTORE_MD_DEFAULT}" != "X" ]
		then
			RESTORE_MD_FLAG=$RESTORE_MD_DEFAULT
		else
			RESTORE_MD_FLAG=0
		fi
	fi
	if [ "X${START_MIRRORING_FLAG}" != "X" -o "X${STOP_MIRRORING_FLAG}" != "X" ]
	then
		echo "${PROGNAME}: Syntax error: Options -m and -M cannot be specified with action 'clean'"
		exit 1
	fi
	;;
*)
	echo "${PROGNAME}: Syntax error: Invalid action ($ACTION)" >&2
	exit 1
	
esac


log INFO "Command $0 executed with ${ACTION} action and parameters: $*"
log INFO "Local file system: ${CDC_HOME_LOCAL_FS}"
log INFO "Shared file system: ${cdc_home_shared_fs}"
log INFO "User: ${MYUSER}"
log INFO "Version: ${VERSION}"

# Retriev/check the instances and execute function, dependent on action specified
retrieveInstances
case "$ACTION" in
start)
	start
	;;
stop)
	stopFunc
	;;
clean)
	clean
	;;
status)
	status
	;;
*)
echo "Usage: $0 start|stop|status|clean"
	exit 1
	;;
esac
