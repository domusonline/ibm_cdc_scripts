#!/bin/ksh
#------------------------------------------------------------------------------
# Copyright (c) 2017 Fernando Nunes
# License: This script is licensed as Apache ( http://www.apache.org/licenses/LICENSE-2.0.html )
# $Author: Fernando Nunes - domusonline@gmail.com $
# $Revision: 1.0.48 $
# $Date 2017-06-22 13:24:55$
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
        echo "${PROGNAME}: -V | -h | [-c N ] [-K {SUB1[,SUB2]}] -I INST [-b BLOCK_SIZE] [-a READ_AHEAD_N_LOGS]"
        echo "               -V            shows script version"
        echo "               -h            shows this help"
	echo "               -c N          launch up to N individual curling processes"
	echo "               -K sub1,sub2  force individual curling processes for susbcriptions sub1 and sub2"
	echo "                             even if they're on same log as others or they're close"
	echo "               -I instance1  attach to instance1"
	echo "               -b BS         use BS (KB) as block size"
	echo "               -a N          read ahead N logs and then wait for sub to catch up"
        echo "Ex: ${PROGNAME} -I INSTSRC01 -c 4 -K sub1"
}


#------------------------------------------------------------------------------
# parse the arguments using standard getopts function
#------------------------------------------------------------------------------
get_args()
{
        arg_ok="Vhc:K:I:b:a:"
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
                K)   # set up the locked subscriptions
                        LOCKED_SUBS_FLAG=1
                        LOCKED_SUBS=$OPTARG
                        echo ${LOCKED_SUBS} | egrep "^[a-zA-Z][a-zA-Z0-9\-_]*(,[a-zA-Z][a-zA-Z0-9\-_])*" 1>/dev/null 2>/dev/null
                        RES=$?
                        if [ "X${RES}" != "X0" ]
                        then
                                log ERROR "$$ Syntax error - Lock subs list must be valid subscriptions names separated by commas"
                                return 1
                        fi
                        ;;
                c)   # set up the -c count
                        COUNT_SUBS_FLAG=1
			COUNT_SUBS=$OPTARG
			echo ${COUNT_SUBS} | egrep "^[1-9][0-9]*" 1>/dev/null 2>/dev/null
			RES=$?
			if [ "X${RES}" != "X0" ]
			then
				log ERROR "$$ Syntax error - Count of processes ($COUNT) needs to be a number"
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
				log ERROR "$$ Syntax error - Block size ($BLOCK_SIZE) needs to be a number"
				return 1
			fi
                        ;;
                a)   # set up the -a read ahead
                        READ_AHEAD_FLAG=1
			READ_AHEAD=$OPTARG
			echo ${READ_AHEAD} | egrep "^[1-9][0-9]*" 1>/dev/null 2>/dev/null
			RES=$?
			if [ "X${RES}" != "X0" ]
			then
				log ERROR "$$ Syntax error - Number of read ahead logs ($BLOCK_SIZE) needs to be a number"
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

#------------------------------------------------------------------------------
# obtain a list of current curlings for an instance
#------------------------------------------------------------------------------

get_current_curlings_for_instance()
{
	l_instance=$1
	l_CURLING_LIST=""
	l_flag=0
	ps -ef | grep -e "ksh.*\/curling\.sh .*\-I  *$l_instance" | gawk '{split($0,ARR,"-s");split(ARR[2],ARR1," ");print $2 " " ARR1[1]}' | while read CURRENT_PID CURRENT_SUB
do
	l_flag=1
        echo "${CURRENT_SUB} ${CURRENT_PID}"
done
	echo "na"
	if [ "X${l_flag}" != "X0" ]
	then
		return 0
	else
		return 1
	fi
}


clean_up()
{
	rm -f $TEMP_FILE_CURR_CURLINGS
}

#------------------------------------------------------------------------------
# START of the script. Above are function definitions
#------------------------------------------------------------------------------

PROGNAME=`basename $0`
SCRIPT_DIR=`dirname $0`
VERSION=`echo "$Revision: 1.0.48 $" | cut -f2 -d' '`
TEMP_FILE_CURR_CURLINGS=/tmp/${PROGNAME}_$$_curr_curlings.tmp

trap clean_up 0

# Read the settings from the properties file
if [ -x ${SCRIPT_DIR}/conf/cdc.properties ]
then
	. ${SCRIPT_DIR}/conf/cdc.properties
else
	echo "Cannot include properties file (${SCRIPT_DIR}/conf/cdc.properties). Exiting!" >&2
	exit 1
fi


# Import general functions
if [ -x  "${SCRIPT_DIR}/include/functions.sh" ]
then
	. "${SCRIPT_DIR}/include/functions.sh"
else
	echo "Cannot include functions file (${SCRIPT_DIR}/include/functions.sh). Exiting!" >&2
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


#------------------------------------------------------------------------------
# Verify argument consistency and sets defaults
#------------------------------------------------------------------------------

log INFO "$$ Command $PROGNAME executed with parameters: $*"
log INFO "$$ Version: ${VERSION}"





if [ "X${INSTANCE_FLAG}" != "X1" ]
then
	log ERROR "$$ Requires instance name. Exiting with RC=1"
	exit 1
fi


#51694   2017-01-13 10:33:16.621 CSPROM LOG READER{248}  com.datamirror.ts.util.oracle.OracleRedoNativeApi       logEventCallback()      Completed online redo log file '/dev/rnpocomlog001'. Redo log file processing has been completed for the on-line file '/dev/rnpocomlog001'. The current sequence is 4274477. The low scn is 8614979546584. The low timestamp is Fri Jan 13 10:29:19 2017. The next scn is -. The next timestamp is -.

#82401   2016-12-27 19:17:50.617 RTKS13 LOG READER{42518}        com.datamirror.ts.util.oracle.OracleRedoNativeApi       logEventCallback() Completed archive redo log file '/u00/oranpo/archivedsa/RMSMCH/1_4248760_474504877.dbf'. Redo log file processing has been completed for the archive file '/u00/oranpo/archivedsa/RMSMCH/1_4248760_474504877.dbf'. The current sequence is 4248760. The low scn is 8602491405795. The low timestamp is Tue Dec 27 08:21:26 2016. The next scn is 8602491617542. The next timestamp is Tue Dec 27 08:21:41 2016.

#------------------------------------------------------------------------------
# Main loop. Read the last lines of the dmts_trace file and create a list of
# subscriptions that are reading archive logs.
# 
#------------------------------------------------------------------------------
while true
do
	# Read the settings from the curling properties file
	if [ -x ${SCRIPT_DIR}/conf/curling.properties ]
	then
		. ${SCRIPT_DIR}/conf/curling.properties
	else
		log ERROR "$$ Cannot include properties file ($SCRIPT_DIR/conf/curling.properties). Exiting!"
		exit 1
	fi
	FILE=`get_instance_logfile $INSTANCE`

	if [ ! -r $FILE ]
	then
	        log ERROR "$$ Cannot get trace file... (${FILE}). Exiting!"
	        exit 1
	fi

	get_current_curlings_for_instance $INSTANCE > $TEMP_FILE_CURR_CURLINGS

	if [ "X${COUNT_SUBS_FLAG}" = "X1" ]
	then
		COUNT_AWK_FLAG="-v COUNT_SUBS=$COUNT_SUBS"
	else
		if [ "X${DEFAULT_COUNT_SUBS}" != "X" ]
		then
			COUNT_AWK_FLAG="-v COUNT_SUBS=$DEFAULT_COUNT_SUBS"
		else
			COUNT_AWK_FLAG=""
		fi
	fi

	if [ "X${LOCKED_SUBS_FLAG}" = "X1" ]
	then
		LOCKED_AWK_FLAG="-v LOCKED_SUBS=$LOCKED_SUBS"
	else
		if [ "X${DEFAULT_LOCKED_SUBS}" != "X" ]
		then
			LOCKED_AWK_FLAG="-v LOCKED_SUBS=$DEFAULT_LOCKED_SUBS"
		else
			LOCKED_AWK_FLAG=""
		fi
	fi

	SUBSCRIPTION_LIST=`generate_subs_list $INSTANCE ANY`

#144402  2017-04-26 14:51:15.726 RTKS14 LOG READER{47950}        com.datamirror.ts.util.TsThread run()   Thread end normal
	tail -$MASTER_CURLING_LOG_LINES $FILE | egrep -e " LOG READER.*com.datamirror.ts.util.oracle.OracleRedoNativeApi.*(Completed archive redo log file|Completed online redo log file)" -e "has started using the single scrape staging store" -e "LOG READER\{.*Thread end normal" | gawk -v CURR_CURLING_FILE=$TEMP_FILE_CURR_CURLINGS $COUNT_AWK_FLAG $LOCKED_AWK_FLAG -v MASTER_CURLING_LOG_MARGIN=$MASTER_CURLING_LOG_MARGIN -v SUBSCRIPTION_LIST="$SUBSCRIPTION_LIST" '
	
	function add_to_start(l_sub)
	{
		if ( LIST_TO_START == "" )
			LIST_TO_START=l_sub
		else
			LIST_TO_START=LIST_TO_START" "l_sub
	}

	function add_to_stop(l_sub)
	{
		if ( LIST_TO_STOP == "" )
			LIST_TO_STOP=l_sub
		else
			LIST_TO_STOP=LIST_TO_STOP" "l_sub
	}

	function order_subs()
	{
		for (i in TMP_ARR_SUBS )
			if ( TMP_ARR_SUBS[i] != -1)
			        tmpidx[sprintf("%12s", TMP_ARR_SUBS[i]),i]=i
	        num=asorti(tmpidx)
	        j = 0
	        for (i=1; i<=num; i++) {
	                split(tmpidx[i], tmp, SUBSEP)
	                indices[++j] = tmp[2]  # tmp[2] is the name
	        }
		SUBS_ORDERED=""
	        for (i=1; i<=num; i++)
		{
			ARR_SUBS[indices[i]]=TMP_ARR_SUBS[indices[i]]
			if ( SUBS_ORDERED == "" )
			{
				SUBS_ORDERED=indices[i]
			}
			else
			{
				SUBS_ORDERED=SUBS_ORDERED" "indices[i]
			}
			print "DEBUG: During order "indices[i]": "ARR_SUBS[indices[i]]
		}
	}
	
	BEGIN {

		print "DEBUG: Instance subscription list: "SUBSCRIPTION_LIST
		split(SUBSCRIPTION_LIST, TMP_ARR, " ")
		for (SUB1 in TMP_ARR)
		{

			SUBSCRIPTION_LIST_ARR[TMP_ARR[SUB1]]=""
		}
		SUBSCRIPTION_LIST_ARR["SHAREDSCRAPE"]="-1"

		#------------------------------------------------------
		# Locked subs
		#------------------------------------------------------
		NUM_LOCKED=split(LOCKED_SUBS,TMP_ARR,",")
		for(i=1;i<=NUM_LOCKED;i++)
			if ( TMP_ARR[i] in SUBSCRIPTION_LIST_ARR )
				LOCKED_SUBS_ARR[TMP_ARR[i]]=""
		for (SUB1 in LOCKED_SUBS_ARR)
			print "DEBUG Locked SUB: "SUB1

		#------------------------------------------------------
		# Limit curling background processes?
		# If not defined use a huge value for simplicity
	       	# (instead of a flag)
		#------------------------------------------------------
		if ( "X"COUNT_SUBS == "X" )
		{
			print "DEBUG: No count_subs specified. Using 1000"
			COUNT_SUBS=1000
		}
		else
		{
			print "DEBUG: count_subs specified: "COUNT_SUBS
		}

		#------------------------------------------------------
		# Load current curlings if existing curlings are provided
		#------------------------------------------------------
		do
		{
			
			getline<CURR_CURLING_FILE
			if ( $0 != "na" )
			{
				split($0,SUB_LINE," ")
				CURR_SUB_ARR[SUB_LINE[1]]=SUB_LINE[2]
			}
		}
		while ( $0 != "na" )

		#For debug:
		for (SUB1 in CURR_SUB_ARR)
		{
			print "DEBUG: Curr "SUB1" "CURR_SUB_ARR[SUB1]
		}
	}


	{
		if ( $0  ~ /has started using the single scrape staging store/ )
		{
			# got the message of joining the shared scrape
			SUB=$11
			LOG=-1
		}
		else
		{
			if ( $0 ~ /LOG READER.*Thread end normal$/ )
			{
				SUB=$4
				LOG=-1
			}
			else
			{
				SUB=$4
				if (! (SUB in SUBSCRIPTION_LIST_ARR ) )
					next
				
				if ( $0 ~ /Completed archive/ )
				{
					LOG=$31
					gsub(/\./,"",LOG)
				}
				else
				{
					if ( $0 ~ /Completed online/ )
						LOG=-1
					else
					{
						print "Invalid line!"
						exit 1
					}
				}
			}
		}
	
		TMP_ARR_SUBS[SUB]=LOG
	}

	END {
	
		for (SUB in TMP_ARR_SUBS)
		{
			print "DEBUG (to have curling before order): "SUB" : "TMP_ARR_SUBS[SUB]
		}
		order_subs()
		LIST_TO_START=""
		LIST_TO_KILL=""
		SUBS_TO_START=0
		PREV_SUB=""
		ADDED_SUBS=0
		NUM_ORDERED=split(SUBS_ORDERED,ORDERED_ARR," ")
		for (i=1;i<=NUM_ORDERED;i++)
		{
			SUB=ORDERED_ARR[i]
			print "DEBUG (to have curling): "SUB" : "ARR_SUBS[SUB]
		}
		for (i=1;i<=NUM_ORDERED;i++)
		{
			SUB=ORDERED_ARR[i]
			#-----------------------------------------------------
			# Verify if we should keep it
			#-----------------------------------------------------
			if ( SUB in LOCKED_SUBS_ARR )
			{
				if ( ! (SUB in CURR_SUB_ARR) )
				{
					print "DEBUG: Added "SUB" because it was specified as locked"
					add_to_start(SUB)
				}
				ADDED_SUBS++
				PREV_SUB=SUB
				continue
			}

			if ( ADDED_SUBS >= COUNT_SUBS )
			{				
				delete ARR_SUBS[SUB]
				print "DEBUG: DELETED "SUB" because max number of curlings was reached"
				continue
			}
			else
			{
				if ( PREV_SUB != "" ) 
				{
					if ( ARR_SUBS[SUB] >= (ARR_SUBS[PREV_SUB] + MASTER_CURLING_LOG_MARGIN) )
					{
						if ( ! (SUB in CURR_SUB_ARR) )
						{
							print "DEBUG: Added "SUB" because it requires curling and has no close neighbour"
							add_to_start(SUB)
						}
						ADDED_SUBS++
						PREV_SUB=SUB
					}
					else
					{
						delete ARR_SUBS[SUB]
						print "DEBUG: DELETED "SUB" because it has a close neighbour ("PREV_SUB")"
					}
				}
				else
				{
					if ( ! (SUB in CURR_SUB_ARR) )
					{
						print "DEBUG: Added "SUB" at head of list"
						add_to_start(SUB)
					}
					ADDED_SUBS++
					PREV_SUB=SUB
				}
			}

		}

		for (SUB1 in CURR_SUB_ARR)
		{
			if ( ! (SUB1 in ARR_SUBS) )
			{
				print "DEBUG: Adding "SUB1" to kill list"
				add_to_stop(SUB1)
			}
		}

		print "TOSTART:"LIST_TO_START
		print "TOKILL:"LIST_TO_STOP
	}' | while read MY_LINE
	do
		case $MY_LINE in
		TOSTART*)
			LIST=`echo $MY_LINE | cut -f2 -d':'`
			for SUBSCRIPTION in $LIST
			do
				nohup $SCRIPT_DIR/curling.sh -I $INSTANCE -s $SUBSCRIPTION 1>/dev/null 2>/dev/null &
				log INFO "$$ Launched background curling. Instance: $INSTANCE Sub: $SUBSCRIPTION PID: $!"
			done
			;;
		TOKILL*)
			LIST=`echo $MY_LINE | cut -f2 -d':'`
			log DEBUG "$$ List of subscriptions to kill from AWK: $LIST"
			for SUBSCRIPTION in $LIST
			do
				grep "^$SUBSCRIPTION" $TEMP_FILE_CURR_CURLINGS | read dummy PID
				ps -ef | grep " $PID .*curling.* $SUBSCRIPTION" >/dev/null
				if [ $? = 0 ]
				then
					kill -15 $PID
					log INFO "$$ Sent signal 15 to PID $PID for sub $SUBSCRIPTION"
				else
					log WARNING "$$ PID $PID returned from AWK for sub $SUBSCRIPTION could not be verified"
				fi
			done
			;;
		DEBUG*)
			log DEBUG "$$ DEBUG message from AWK ($MY_LINE)"
			;;
		*)
			log ERROR "$$ Invalid output from AWK ($MY_LINE). Exiting"
			exit 1
			;;
		esac
	done	
	log DEBUG "$$ -------------------------------------------- Sleeping -------------------------------------"
	sleep $MASTER_CURLING_INTERVAL
done

