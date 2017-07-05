#!/bin/ksh
#--------------------------------------------------------------------------------------------------
# Copyright (c) 2017 Fernando Nunes
# License: This script is licensed as Apache ( http://www.apache.org/licenses/LICENSE-2.0.html )
# $Author: Fernando Nunes - domusonline@gmail.com $
# $Revision: 1.0.53 $
# $Date 2017-07-05 15:02:29$
# Disclaimer: This software is provided AS IS, without any kind of guarantee. Use at your own risk.
#--------------------------------------------------------------------------------------------------

#------------------------------------------------------------------------------
# Function definitions
#------------------------------------------------------------------------------

#------------------------------------------------------------------------------
# show command syntax
#------------------------------------------------------------------------------

show_help()
{
	echo "${PROGNAME}: -V | -h | -S <source> -T <target> [-l tail_limit] [-t threshold]"
	echo "               -V shows script version"
	echo "               -h shows this help"
	echo "               -I source        : source instance"
	echo "               -T target        : target instance"
	echo "               -l tail_limit    : number of lines of history to search for last value"
	echo "               -t threshold     : default value for slow db ops increase that triggers alarms"
        echo "Ex: ${PROGNAME} -S RTKSRC01 -T RTKTGT01"
}

#------------------------------------------------------------------------------
# Send an email alert
#------------------------------------------------------------------------------
alert_mail()
{
	BODY_TYPE=$1
	case $BODY_TYPE in
	PARAM)
		shift
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
		;;
	FILE)
		cat <<EOF! > $TEMP_FILE_MAIL
FROM: $ALARM_FROM
TO: $ALARM_TO
CC: $ALARM_CC
SUBJECT: $ALARM_SUBJECT
----------------------------------------------------------
EOF!
		cat $TEMP_FILE_BODY >> $TEMP_FILE_MAIL
		cat <<EOF! >> $TEMP_FILE_MAIL

----------------------------------------------------------
.
EOF!

		${SENDMAIL} ${SENDMAIL_OPTIONS} < $TEMP_FILE_MAIL
		;;
	*)
		log WARNING "$$ Invalid body type in alert_email()"
	esac
}






#------------------------------------------------------------------------------
# Get previous value of slow DB ops for a subscription
#------------------------------------------------------------------------------

get_prev_ops_count()
{
	if [ $# != 3 ]
	then
		log ERROR "$$ get_prev_ops_count() called with wrong number of parameters ($#)"
		exit 1
	fi

	tail -$TAIL_LIMIT $SLOW_DB_OPS_HIST_FILE | awk -v s_Instance=$1 -v t_Instance=$2 -v subscription=$3 'BEGIN {
		PREV_COUNT="na"
		}
		{
			if ( $3 == s_Instance && $4 == t_Instance && $5 == subscription )
			{
				if ( $6 ~ /^[0-9][0-9]*$/ )
				{
					PREV_COUNT=$6
				}
			}
		}
		END {
			print PREV_COUNT
		}'
}

#------------------------------------------------------------------------------
# parse the arguments using standard getopts function
#------------------------------------------------------------------------------
get_args()
{
	arg_ok="VhS:T:l:t:"
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
		S)      #source instance
			SOURCE_INSTANCE_FLAG=1
			SOURCE_INSTANCE=$OPTARG
			;;
		T)      #target instance
			TARGET_INSTANCE_FLAG=1
			TARGET_INSTANCE=$OPTARG
			;;
		l)	# Tail limit
			TAIL_LIMIT_FLAG=1
			TAIL_LIMIT=$OPTARG
			;;
		t)	# Threshold
			THRESHOLD_FLAG=1
			THRESHOLD_DEFAULT=$OPTARG
			;;
                *)
                        log ERROR "$$ Invalid parameter (${OPTION}) given"
                        return 1
                        ;;
		esac
	done
	if [ ${NUM_ARGUMENTS} -ge ${OPTIND} ]
	then
		log ERROR "$$ Syntax error: Too many parameters" >&2
		return 2
	fi
	return 0
}

#------------------------------------------------------------------------------
# Check for errors after executing chcclp
#------------------------------------------------------------------------------
check_errors()
{
	grep -e ERR2225 -e "lready connected" -e ERR ${TEMP_FILE} >/dev/null
	if [ $? = 0 ]
	then
		return 1
	else
		return 0
	fi
}

#------------------------------------------------------------------------------
# Cleaning up temp files
#------------------------------------------------------------------------------
clean_up()
{
	rm -f $TEMP_FILE $TEMP_FILE_SUB $TEMP_FILE_SUB_SLOW $TEMP_FILE_SLOW_DB_SRT $TEMP_FILE_MAIL $TEMP_FILE_BODY
}


#------------------------------------------------------------------------------
#START
#------------------------------------------------------------------------------

DEBUG=0
PROGNAME=`basename $0`
SCRIPT_DIR=`dirname $0`
if [ "X${SCRIPT_DIR}" = "X." ]
then
	SCRIPT_DIR=`pwd`
fi

VERSION=`echo "$Revision: 1.0.53 $" | cut -f2 -d' '`

TEMP_FILE=/tmp/${PROGNAME}_$$.tmp
TEMP_FILE_SUB=/tmp/${PROGNAME}_SUB_$$.tmp
TEMP_FILE_SUB_SLOW=/tmp/${PROGNAME}_SUB_SLOW_$$.tmp
TEMP_FILE_SLOW_DB_SRT=/tmp/${PROGNAME}_SLOW_DB_SRT_$$.tmp
TEMP_FILE_BODY=/tmp/${PROGNAME}_BODY_$$.tmp
TEMP_FILE_MAIL=/tmp/${PROGNAME}_MAIL$$.tmp

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

# Read the settings from the slow db properties file
if [ -x ${SCRIPT_DIR}/conf/slow_db.properties ]
then
	. ${SCRIPT_DIR}/conf/slow_db.properties
else
	log ERROR "$$ Cannot include properties file (${SCRIPT_DIR}/conf/slow_db.properties). Exiting!"
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


if [ "X${TAIL_LIMIT_FLAG}" != "X1" ]
then
	TAIL_LIMIT=100
fi
LOOP_LIMIT=5
LOOP_SLEEP=30


cd $CDC_AS_HOME/bin

LOOP_COUNT=1
while [ ${LOOP_COUNT} -le ${LOOP_LIMIT} ]
do
	./chcclp -f ${SCRIPT_DIR}/check_cdc_status.chcclp hostname:$AS_SERVER port:$AS_PORT username:$AS_USER password:$AS_PWD source:$SOURCE_INSTANCE target:$TARGET_INSTANCE > $TEMP_FILE
	check_errors
	if [ $? = 0 ]
	then
		cp $TEMP_FILE $TEMP_FILE_SUB
		break
	else
		log INFO "$$ Iteraction $LOOP_COUNT of loop to get subscriptions had errors"
		promoteLog $TEMP_FILE
		LOOP_COUNT=`expr $LOOP_COUNT + 1`
		sleep $LOOP_SLEEP
	fi
done
if [ $LOOP_COUNT -gt ${LOOP_LIMIT} ]
then
	log ERROR "$$ Loop limit ($LOOP_LIMIT) reached in chcclp command to list of subscriptions. Exiting!"
	promoteLog $TEMP_FILE
	exit 3
fi
	

if [ ${DEBUG} != 0 ];then echo "=============== Subscription list: ===================";cat $TEMP_FILE_SUB;echo "=============== End Subscription list: ===================";fi

		
CURR_DATE=`date +"%Y-%m-%d %H:%M:%S"`
ALARM_SUBJECT="Slow DB Operations on source instance $SOURCE_INSTANCE. Check body for details."
cat /dev/null > $TEMP_FILE_BODY
ALERT_FLAG=0

SUBS=`cat $TEMP_FILE_SUB | grep Mirror | cut -f1 -d " "`
for SUBSCRIPTION in $SUBS
do
	ALERT_FILE=${SCRIPT_DIR}/tmp/.${PROGNAME}_${SUBSCRIPTION}
	if [ ${DEBUG} != 0 ];then log DEBUG "Processing stats for active subscription $SUBSCRIPTION";fi


	THRESHOLD=`eval 'echo $CDC_THRESHOLD_SLOW_DB_OPS_'${SUBSCRIPTION}`
	if [ "X${THRESHOLD}" = "X" ]
	then
		if [ "X${THRESHOLD_FLAG}" = "X" ]
		then
			THRESHOLD=${CDC_THRESHOLD_SLOW_DB_OPS}
			if [ "X${THRESHOLD}" = "X" ]
			then
				log ERROR "$$ Could not obtain default threshold for slow database operations monitor (from config). Exiting!"
				exit 2
			fi
		else
			THRESHOLD=$THRESHOLD_DEFAULT
		fi
	fi
	
	LOOP_COUNT=1;while [ ${LOOP_COUNT} -le ${LOOP_LIMIT} ]
	do
		./chcclp -f ${SCRIPT_DIR}/get_slow_db_ops.chcclp hostname:$AS_SERVER port:$AS_PORT username:$AS_USER password:$AS_PWD source:$SOURCE_INSTANCE target:$TARGET_INSTANCE subscription:$SUBSCRIPTION > $TEMP_FILE
		check_errors
		if [ $? = 0 ]
		then
			cp $TEMP_FILE $TEMP_FILE_SUB_SLOW
			break
		else
			LOOP_COUNT=`expr $LOOP_COUNT + 1`
		fi
	done
	if [ $LOOP_COUNT -gt ${LOOP_LIMIT} ]
	then
		log WARNING "$$ Loop limit ($LOOP_LIMIT) reached in chcclp command to get metric for subscription $SUBSCRIPTION. Skipping to next subscription"
		promoteLog $TEMP_FILE
		continue
	fi


	if [ ${DEBUG} != 0 ];then echo "=============== Subscription $SUBCRIPTION output: ===================";cat $TEMP_FILE_SUB_SLOW;echo "=============== End Subscription $SUBSCRIPTION output: ===================";fi

	#Extract line with slow ops count
	slow_ops_count=`cat $TEMP_FILE_SUB_SLOW | grep " Target Apply" `

	#Trim initial blanks anc collapse multiple medial consecutive blanks to 1 blank
	slow_ops_count=`echo $slow_ops_count`

	#Get slow ops count by field count
	slow_ops_count=`echo $slow_ops_count | cut -f9 -d " " | sed 's/,//g'`

	echo $slow_ops_count | grep "^[0-9][0-9]*$" >/dev/null
	if [ $? != 0 ]
	then
		#Couldn't get a proper metric... skip
		log WARNING "$$ Couldn't get a proper metric for susbsciption $SUBSCRIPTION: Obtained: $slow_ops_count"
		promoteLog $TEMP_FILE_SUB_SLOW
		continue
	fi

	prev_slow_ops_count=`get_prev_ops_count $SOURCE_INSTANCE $TARGET_INSTANCE $SUBSCRIPTION`
	if [ "X${prev_slow_ops_count}" = "Xna" ]
	then
		echo "$CURR_DATE $SOURCE_INSTANCE $TARGET_INSTANCE $SUBSCRIPTION $slow_ops_count" >> $SLOW_DB_OPS_HIST_FILE
		continue
	fi

	diff_slow_ops_count=`expr $slow_ops_count - $prev_slow_ops_count`
	if [ $diff_slow_ops_count -lt 0 ]
	then
		#Subscription was probably restarted. Clean all alarms
		rm -rf ${ALERT_FILE}
		ALERT_FLAG=1
		echo "Subscription $SUBSCRIPTION ($SOURCE_INSTANCE - $TARGET_INSTANCE) slow db ops counter was reset" >> $TEMP_FILE_BODY
		echo  >> $TEMP_FILE_BODY
	else
		if [ ${DEBUG} != 0 ];then echo DIFF: $diff_slow_ops_count THRESHOLD: $THRESHOLD; fi
		if [ $diff_slow_ops_count -ge $THRESHOLD ]
		then
			#Diference between last value and current one is bigger than threshold, so alert
			alert_notification ${SOURCE_INSTANCE} DEFAULT ${SUBSCRIPTION} DEFAULT "Warning" "SlowDBOps" "Subscription $SUBSCRIPTION ($SOURCE_INSTANCE - $TARGET_INSTANCE) increased the Slow DB Ops counter ($slow_ops_count) by ${diff_slow_ops_count}. Threshold is ${THRESHOLD}"
			if [ -r "${ALERT_FILE}" ]
			then
				cat ${ALERT_FILE} | read ALERT_COUNT
				ALERT_COUNT=`expr ${ALERT_COUNT} + 1`
			else
				ALERT_COUNT=1
			fi
			if [ ${ALERT_COUNT} -le ${ALERT_COUNT_LIMIT} ]
			then
				echo "Subscription $SUBSCRIPTION ($SOURCE_INSTANCE - $TARGET_INSTANCE) increased the Slow DB Ops counter ($slow_ops_count) by ${diff_slow_ops_count}. Threshold is ${THRESHOLD}" >> $TEMP_FILE_BODY
				echo >> $TEMP_FILE_BODY
				ALERT_FLAG=1
			fi
			echo ${ALERT_COUNT} > ${ALERT_FILE}
		else
			#Diference is below the limit, so clear any alarm count file if exists
			if [ -r ${ALERT_FILE} ]
			then
				rm -rf ${ALERT_FILE}
				echo "Subscription $SUBSCRIPTION ($SOURCE_INSTANCE - $TARGET_INSTANCE) return to a value ($diff_slow_ops_count) below the threashold ($THRESHOLD)" >> $TEMP_FILE_BODY
				echo  >> $TEMP_FILE_BODY
				ALERT_FLAG=1
			fi
		fi
	fi

	echo "$CURR_DATE $SOURCE_INSTANCE $TARGET_INSTANCE $SUBSCRIPTION $slow_ops_count" >> $SLOW_DB_OPS_HIST_FILE
	if [ ${DEBUG} != 0 ]; then echo "`date` $SOURCE_INSTANCE $TARGET_INSTANCE $SUBSCRIPTION $slow_ops_count";fi
done

if [ $ALERT_FLAG = 1 ]
then
	alert_mail FILE
fi
