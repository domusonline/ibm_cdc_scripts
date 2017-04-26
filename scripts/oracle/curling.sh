#!/bin/ksh
#------------------------------------------------------------------------------
# Copyright (c) 2017 Fernando Nunes
# License: This script is licensed as Apache ( http://www.apache.org/licenses/LICENSE-2.0.html )
# $Author: Fernando Nunes - domusonline@gmail.com $
# $Revision: 1.0.27 $
# $Date 2017-04-26 16:53:40$
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
        echo "${PROGNAME}: -V | -h | {-s SUB1 -I INST} [-b BLOCK_SIZE] [-a READ_AHEAD_N_LOGS]"
        echo "               -V shows script version"
        echo "               -h shows this help"
	echo "               -s SUB               : do curling for subscription SUB"
	echo "               -I INST              : do curling for instance INST"
	echo "               -b BLOCK_SIZE        : use BLOCK_SIZE in read() ops (KBs)"
	echo "               -a READ_AHEAD_N_LOGS : read this number of logs in advance"
        echo "Ex: ${PROGNAME} -I INSTSRC01 -s SUB1 -b 256 -a 1"
}

#------------------------------------------------------------------------------
# parse the arguments using standard getopts function
#------------------------------------------------------------------------------

get_args()
{
	arg_ok="Vhs:I:b:a:"
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
		s)   # set up the locked subscriptions
			SUBSCRIPTION_FLAG=1
			SUBSCRIPTION=$OPTARG
			echo ${SUBSCRIPTION} | egrep "^[a-zA-Z][a-zA-Z0-9\-_]*(,[a-zA-Z][a-zA-Z0-9\-_])*" 1>/dev/null 2>/dev/null
			RES=$?
			if [ "X${RES}" != "X0" ]
			then
				log ERROR "$$ Syntax error - Subscription ($SUBSCRIPTION) is invalid" >&2
				return 1
			fi
			;;
		b)   # set up the -b block size
			BLOCK_SIZE_FLAG=1
			BLOCK_SIZE=$OPTARG
			echo ${BLOCK_SIZE} | egrep "^[1-9][0-9]*" 1>/dev/null 2>/dev/null
			RES=$?
			if [ "X${RES}" != "X0" ]
			then
				log ERROR "$$ Syntax error - Block size ($BLOCK_SIZE) needs to be a number" >&2
				return 1
			else
				BLOCK_SIZE=`expr $BLOCK_SIZE \* 1204`
			fi
			;;
		a)   # set up the -a read ahead
			READ_AHEAD_FLAG=1
			READ_AHEAD=$OPTARG
			echo ${READ_AHEAD} | egrep "^[1-9][0-9]*" 1>/dev/null 2>/dev/null
			RES=$?
			if [ "X${RES}" != "X0" ]
			then
				log ERROR "$$ Syntax error - Number of read ahead logs ($BLOCK_SIZE) needs to be a number" >&2
				return 1
			fi
			;;
		I)   # set up the -I instance
			INSTANCE_FLAG=1
			INSTANCE=$OPTARG
			#instanceIsActive $INSTANCE
			#RES=$?
			#if [ "X${RES}" != "X0" ]
			#then
			#	echo "${PROGNAME}: Instance $INSTANCE does not exist or is not active" >&2
			#	return 1
			#fi
			;;
		*)
			log ERROR "$$ Invalid parameter (${OPTION}) given"
			return 1
			;;
		esac
	done
	return 0
}

clean_up()
{
	rm -f $TEMP_FILE_1
}

#------------------------------------------------------------------------------
# SCRIPT START
#------------------------------------------------------------------------------


PROGNAME=`basename $0`
SCRIPT_DIR=`dirname $0`
VERSION=`echo "$Revision: 1.0.27 $" | cut -f2 -d' '`
TEMP_FILE_1=/tmp/${PROGNAME}_$$.tmp

trap clean_up 0

# Read the settings from the properties file
if [ -x ${SCRIPT_DIR}/conf/cdc.properties ]
then
	. ${SCRIPT_DIR}/conf/cdc.properties
else
	log ERROR "$$ Cannot include properties file (${SCRIPT_DIR}/conf/cdc.properties). Exiting!"
	exit 1
fi

# Import general functions
if [ -x  "${SCRIPT_DIR}/include/functions.sh" ]
then
	. "${SCRIPT_DIR}/include/functions.sh"
else
	log ERROR "$$ Cannot include functions file (${SCRIPT_DIR}/include/functions.sh). Exiting!"
	exit 1
fi

NUM_ARGUMENTS=$#

get_args $*
if [ $? != 0 ]
then
        show_help >&2
	log ERROR "$$ Invalid parameters. Exiting!"
        exit 1
fi

if [ "X${INSTANCE_FLAG}" != "X1" ]
then
	log ERROR "$$ Instance name not provided. Exiting!"
	exit 1
fi

if [ "X${SUBSCRIPTION_FLAG}" != "X1" ]
then
	log ERROR "$$ Subscription name not provided. Exiting!"
	exit 1
fi


NUM_LOGS_BELOW_LIMIT=0
log INFO "$$ Command $PROGNAME executed with parameters: $*"


FIRST=1
LAST_LOG=-1
while true
do
	unset SINGLE_CURLING_LOG_LINES

	if [ -x $SCRIPT_DIR/conf/curling.properties ]
	then
		. $SCRIPT_DIR/conf/curling.properties
	else
		log ERROR "$$ Cannot include properties file ($SCRIPT_DIR/conf/cdc.properties). Exiting!"
		exit 1
	fi

	if [ -z "$FILE" ]
	then
		FILE=`get_instance_logfile $INSTANCE`
	else
		#TODO : if an instance is stopped the log file may be kept without being compressed
		if [ ! -r $FILE ]
		then
			FILE=`get_instance_logfile $INSTANCE`
		fi
	fi
	if [ "X$FLAG_SLEEPING" = "X0" ]
	then
		log INFO "$$ $PROGNAME $FILE SUB: $SUBSCRIPTION"
	fi

	if [ "X${READ_AHEAD_FLAG}" != "X1" ]
	then
		READ_AHEAD=$DEFAULT_READ_AHEAD
	fi
	if [ "X${BLOCK_SIZE_FLAG}" != "X1" ]
	then
		BLOCK_SIZE=`expr $DEFAULT_BLOCK_SIZE \* 1024`
	fi


	if "X{SINGLE_CURLING_LOG_LINES}" = "X" ]
	then
		SINGLE_CURLING_LOG_LINES=200
	fi



#140509  2017-03-15 13:12:21.091 SHAREDSCRAPE{110}       com.datamirror.ts.eventlog.EventLogger  logActualEvent()        Event logged: ID=2922 MSG=Subscription RTKS06 has started using the single scrape staging store. Subscription bookmark: Journal name JOURNAL Journal bookmark 000308;8666272196871;8666537600436.1.1.4043238.108.1;8666537600436.1.1.4043238.108.1.0| Staging store oldest bookmark: Journal name JOURNAL Journal bookmark 000308;8666272196871;8666537591747.1.1.4020119.200.1;8666537591744.1.1.4020111.456.1.0| Staging store newest bookmark: Journal name JOURNAL Journal bookmark 000308;8666272196871;8666537601308.1.1.4044752.436.1;8666537601308.1.1.4044752.436.1.0|
#                                 $SUBS LOG READER.*com.datamirror.ts.util.oracle.OracleRedoNativeApi.*(Completed archive redo log file|Completed online redo log file)"
	tail -${SINGLE_CURLING_LOG_LINES} $FILE | egrep -u -e "$SUBSCRIPTION LOG READER\{.*Thread end normal" -e "$SUBSCRIPTION has started using the single scrape staging store" -e "$SUBSCRIPTION LOG READER.*com.datamirror.ts.util.oracle.OracleRedoNativeApi.*(Completed archive redo log file|Completed online redo log file)" | tail -1 | awk -u '
/Completed archive redo/ {
LOG=$31
gsub(/\./,"",LOG)
LOG_OUT=LOG
}

/Completed online redo/ {
LOG_OUT="REDO"
}

/LOG READER.*Thread end normal/ {
LOG_OUT="SHARED"
}

/has started using the single scrape staging store/ {
LOG_OUT="SHARED"
}

END {
	print LOG_OUT
}
' | read LOG

	if [ "X$LOG" = "XSHARED" ]
	then
		log INFO "$$ Subscription $SUBSCRIPTION joined the shared scrape or was stopped. Exiting"
		exit 0
	fi

	if [ "X$LOG" = "XREDO" ]
	then
		log INFO "$$ Subscription $SUBSCRIPTION reached the online redos. Exiting"
		exit 0
	fi

	if [ ! -n "$LOG" ]
	then
		if [ "X$FLAG_SLEEPING" != "X2" ]
		then
			log INFO "$$ LOG was empty. slept and will skip..."
			FLAG_SLEEPING=2
		fi
		sleep $WAIT_FOR_SUB_SECONDS
		continue
	fi 


	if [ $FIRST = 1 ]
	then
		FIRST=0
		PREV_LOG=`expr $LOG + 1`
	fi

	
	
	AUX1=`expr $PREV_LOG - 1`
	if [ \( $LOG -ge $AUX1 \) -o \( $LOG -lt $LAST_LOG \) ]
	then
		AUX2=`expr $PREV_LOG + $READ_AHEAD`
		CURR_LOG=`expr $PREV_LOG + 1`
		log INFO "$$ $PROGNAME Last seen log=$LOG. Reading from $CURR_LOG through $AUX2"
			

		while [ $CURR_LOG -le $AUX2 ]
		do
			CONT=1
			LOOP_ORA=0
			CDC_ORA_INIT_OFFSET=0
			PART_LOG_SIZE=$CDC_ORA_PART_SIZE
			LOG_FILE="naoexiste"
			ls $CDC_ORACLE_LOG_LOCATION/1_${CURR_LOG}_*.dbf | read LOG_FILE
			if [ $? != 0 ]
			then
				log INFO "$$ Log file ($LOG_FILE) can't be read"
				sleep 120
				ls $CDC_ORACLE_LOG_LOCATION/1_${CURR_LOG}_*.dbf | read LOG_FILE
				if [ $? != 0 ]
				then
					log WARNING "$$ Log file ($LOG_FILE) can't be read after 120s. Exiting!"
					exit 1
				else
					if [ ! -r $LOG_FILE ]
					then
						log WARNING "$$ Log file ($LOG_FILE) can't be read after 120s wait and successful ls. Exiting!"
						exit 1
					fi
				fi
			else
				if [ ! -r $LOG_FILE ]
				then
					log WARNING "$$ Log file ($LOG_FILE) can't be read after successful ls. Exiting!"
					exit 1
				fi
			fi
			ls -l $LOG_FILE | awk '{print $5}' | read ORA_CURR_LOG_SIZE
			if [ $? != 0 ]
			then
				log ERROR "$$ Critical failure obtaining log file size. Exiting!"
				exit 2
			fi
			CDC_LAST_BLOCK=`expr $ORA_CURR_LOG_SIZE - $CDC_ORA_PART_SIZE`
			LOG_START_TIME=`date +"%s"`
			if [ "X${DEBUG}" != "X0" ];then log DEBUG "$$ Start log. PART_LOG_SIZE=$PART_LOG_SIZE CDC_LAST_BLOCK=$CDC_LAST_BLOCK ORA_CURR_LOG_SIZE=$ORA_CURR_LOG_SIZE";fi

			while [ $CONT = 1 ]			
			do
				if [ $PART_LOG_SIZE = 0 ]
				then
					CONT=0
				fi
				
				$CDC_READ_AHEAD_CMD $CDC_ORACLE_LOG_LOCATION/1_${CURR_LOG}_*.dbf ${BLOCK_SIZE} $CDC_ORA_INIT_OFFSET $PART_LOG_SIZE 1>>$TEMP_FILE_1 2>&1 &
				LOOP_ORA=`expr $LOOP_ORA + 1`
				CDC_ORA_INIT_OFFSET=`expr $CDC_ORA_INIT_OFFSET + $CDC_ORA_PART_SIZE`
				
				if [ $LOOP_ORA -ge $CDC_MAX_PARALLEL_JOBS ]
				then
					LOOP_ORA=0
					wait
					promoteLog $TEMP_FILE_1
					rm -f $TEMP_FILE_1
				fi
				if [ $CDC_ORA_INIT_OFFSET -ge $CDC_LAST_BLOCK ]
				then
					PART_LOG_SIZE=0
				fi
			done
			CURR_LOG=`expr $CURR_LOG + 1`
			LOG_STOP_TIME=`date +"%s"`
			LOG_CURR_INTERVAL=`expr $LOG_STOP_TIME - $LOG_START_TIME`
			if [ $LOG_CURR_INTERVAL -le $LOG_READ_LIMIT ] 
			then
				NUM_LOGS_BELOW_LIMIT=`expr $NUM_LOGS_BELOW_LIMIT + 1`
			else
				NUM_LOGS_BELOW_LIMIT=0
			fi
			

			if [ $NUM_LOGS_BELOW_LIMIT -ge $NUM_LOGS_BELOW_LIMIT_EXIT ]
			then
				log INFO "$$ Sequence of logs reading below limit. Quitting!"
				exit 0
			fi

		done
		PREV_LOG=`expr $CURR_LOG - 1`
		FLAG_SLEEPING=0
	else
		if [ "X$FLAG_SLEEPING" != "X1" ]
		then
			log INFO "$$ Last seen LOG: $LOG. Prev ahead log: $PREV_LOG - Sleeping"
		fi
		sleep $WAIT_FOR_SUB_SECONDS
		FLAG_SLEEPING=1
	fi
	LAST_LOG=$LOG
done
