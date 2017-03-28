#!/bin/ksh
# Copyright (c) 2017 Fernando Nunes - fernando.nunes@pt.ibm.com
# License: This script is licensed as Apache ( http://www.apache.org/licenses/LICENSE-2.0.html )
# $Author: Fernando Nunes - domusonline@gmail.com $
# $Revision: .1 $
# $Date 2017-03-28 08:41:17$
# Disclaimer: This software is provided AS IS, without any kind of guarantee. Use at your own risk.

show_help()
{
	echo "${PROGNAME}: -V | -h | <INSTANCE> <SUBSCRIPTION[,SUBSCRIPTION]>"
	echo "               -V shows script version"
	echo "               -h shows this help"
	echo "Ex: ${PROGNAME} RTKSRC01 ALL"
}

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
		esac
	done

	if [ ${NUM_ARGUMENTS} -ge ${OPTIND} ]
	then
		shift `expr $OPTIND - 1`
		if [ $# -lt 2 ]
		then
			echo "${PROGNAME}: Syntax error: Too many or too few parameters" >&2
			return 2
		else
			INSTANCE=$1
			shift
			FIRST=1
			for SUB in $*
			do
				if [ $SUB = "ALL" ]
				then
					SUBS='..*'
					break
				fi
				if [ $FIRST = 1 ]
				then
					SUBS="($SUB"
					FIRST=0
				else
					SUBS="$SUBS|$SUB"
				fi
			done
			return 0
		fi
	else
		echo "${PROGNAME}: Syntax error: Too few parameters" >&2
		return 2
	fi
	return 0
}

do_tail()
{
echo Trace file: $FILE
echo Subs: "$SUBS"
#51694   2017-01-13 10:33:16.621 CSPROM LOG READER{248}  com.datamirror.ts.util.oracle.OracleRedoNativeApi       logEventCallback()      Completed online redo log file '/dev/rnpocomlog001'. Redo log file processing has been completed for the on-line file '/dev/rnpocomlog001'. The current sequence is 4274477. The low scn is 8614979546584. The low timestamp is Fri Jan 13 10:29:19 2017. The next scn is -. The next timestamp is -.

#RTKSRC01 375044 2017-01-31 19:27:20.417 RTKS13 1_4286561_474504877.dbf 4286561 8628455073539 Jan 31 08:54:46 2017 Jan 31 08:55:49 2017 46
#82401   2016-12-27 19:17:50.617 RTKS13 LOG READER{42518}        com.datamirror.ts.util.oracle.OracleRedoNativeApi       logEventCallback()      Completed archive redo log file '/u00/oranpo/archivedsa/RMSMCH/1_4248760_474504877.dbf'. Redo log file processing has been completed for the archive file '/u00/oranpo/archivedsa/RMSMCH/1_4248760_474504877.dbf'. The current sequence is 4248760. The low scn is 8602491405795. The low timestamp is Tue Dec 27 08:21:26 2016. The next scn is 8602491617542. The next timestamp is Tue Dec 27 08:21:41 2016.
tail -f $FILE | egrep -u -e "$SUBS LOG READER.*com.datamirror.ts.util.oracle.OracleRedoNativeApi.*(Completed archive redo log file|Completed online redo log file)" | gawk -v INSTANCE=$INSTANCE '
BEGIN {
}
function month_to_num( mes )
{
	if ( mes == "Jan" )
		return "01"
	else
	if ( mes == "Feb" )
		return "02"
	else
	if ( mes == "Mar" )
		return "03"
	else
	if ( mes == "Apr" )
		return "04"
	else
	if ( mes == "May" )
		return "05"
	else
	if ( mes == "Jun" )
		return "06"
	else
	if ( mes == "Jul" )
		return "07"
	else
	if ( mes == "Aug" )
		return "08"
	else
	if ( mes == "Sep" )
		return "09"
	else
	if ( mes == "Oct" )
		return "10"
	else
	if ( mes == "Nov" )
		return "11"
	else
	if ( mes == "Dec" )
		return "12"
}

/Completed archive redo log file/ {
FILE=$14
gsub(/[\47]\./,"",FILE)
AUX1=split(FILE,AUX,/\//)
gsub(/\.$/,"",AUX[AUX1])
gsub(/\./,"",$31)
gsub(/\./,"",$36)
gsub(/\./,"",$45)
gsub(/\./,"",$59)
START_MONTH=month_to_num($42)
START_DAY=$43
START_HOUR=$44
START_HOUR_AUX=$44
gsub(/:/, " ", START_HOUR_AUX)
START_YEAR=$45

END_MONTH=month_to_num($56)
END_DAY=$57
END_HOUR=$58
END_HOUR_AUX=$58
gsub(/:/, " ", END_HOUR_AUX)
END_YEAR=$59

START_EPOCH=mktime(START_YEAR " " START_MONTH " " START_DAY " " START_HOUR_AUX)
END_EPOCH=mktime(END_YEAR " " END_MONTH " " END_DAY " " END_HOUR_AUX)


SUB=$4
HOUR=$3
split(HOUR,HOUR_AUX,/\./)
CURRENT_TIMESTAMP=$2 " " HOUR_AUX[1]
gsub(/[-:]/," ",CURRENT_TIMESTAMP)
CURRENT_TIMESTAMP=mktime(CURRENT_TIMESTAMP)
if ( SUB in SUBS )
{
	LAST_INTERVAL=(CURRENT_TIMESTAMP - SUBS[SUB])
}
else
{
	LAST_INTERVAL="na"
}
SUBS[SUB]=CURRENT_TIMESTAMP
print INSTANCE " " $1 " " $2 " " $3 " " $4 " " AUX[AUX1] " " $31 " " $36 " " START_YEAR "-" START_MONTH "-" START_DAY " " START_HOUR " " END_YEAR "-" END_MONTH "-" END_DAY " " END_HOUR " " LAST_INTERVAL "/" END_EPOCH-START_EPOCH}

/Completed online redo log file/ {
FILE=$14
gsub(/[\47]\./,"",FILE)
AUX1=split(FILE,AUX,/\//)
gsub(/\.$/,"",AUX[AUX1])
gsub(/\./,"",$31)
gsub(/\./,"",$36)
gsub(/\./,"",$44)
SUB=$4
HOUR=$3
split(HOUR,HOUR_AUX,/\./)
CURRENT_TIMESTAMP=$2 " " HOUR_AUX[1]
gsub(/[-:]/," ",CURRENT_TIMESTAMP)
CURRENT_TIMESTAMP=mktime(CURRENT_TIMESTAMP)
if ( SUB in SUBS )
{
	LAST_INTERVAL=(CURRENT_TIMESTAMP - SUBS[SUB])
}
else
{
	LAST_INTERVAL="n/a"
}
SUBS[SUB]=CURRENT_TIMESTAMP
print INSTANCE " " $1 " " $2 " " $3 " " $4 " " AUX[AUX1] " " $31 " " $36 " " $41 " " $42 " " $43 " " $44 " " LAST_INTERVAL}

' &
MYPID=$!
check_file_background&
BKG_PID=$!
wait

}


kill_all_childs()
{
	kill -9 $BKG_PID
	kill -9 0
}

check_file_background()
{
	
	while true
	do
		sleep $INTERVAL &
		wait
		NEW_FILE=`get_instance_logfile $INSTANCE`
		if [ "$NEW_FILE" != "$FILE" ]
		then
			FILE=$NEW_FILE
			ps -ef | awk -v MYPID=$MYPID '{if ( ($3 == MYPID ) && ( $0 ~ /( gawk | egrep | tail )/ ) ) {print $2}}' | while read PID_TO_KILL
			do
				kill -15 $PID_TO_KILL
			done
			kill -15 $MYPID
			echo "Should restart!"
			return
		fi
	done
}
#--------------------------------------------------------------------------------
#START of script
#--------------------------------------------------------------------------------

INTERVAL=60


PROGNAME=`basename $0`
SCRIPT_DIR=`dirname $0`
VERSION=`echo "$Revision: .1 $" | cut -f2 -d' '`
NUM_ARGUMENTS=$#

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

get_args $*
if [ $? != 0 ]
then
	show_help >&2
	exit 1
fi

FILE=`get_instance_logfile $INSTANCE`

if [ ! -r $FILE ]
then
	printf "$0: Cannot get trace file...\n" >&2
	exit 1
fi

trap kill_all_childs 0 15 2

while true
do
	do_tail
	echo Returned from do_tail
done
