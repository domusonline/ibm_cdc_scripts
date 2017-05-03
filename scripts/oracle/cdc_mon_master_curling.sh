#!/bin/ksh
#---------------------------------------------------------------------------------------------------
# Copyright (c) 2017 Fernando Nunes
# Based on previous script by Frank Ketelaars and Robert Philo
# License: This script is licensed as Apache ( http://www.apache.org/licenses/LICENSE-2.0.html )
# $Author: Fernando Nunes - domusonline@gmail.com $
# $Revision: 1.0.43 $
# $Date 2017-05-03 18:14:16$
# Disclaimer: This software is provided AS IS, without any kind of guarantee. Use at your own risk.
#---------------------------------------------------------------------------------------------------


#------------------------------------------------------------------------------
# show command syntax
#------------------------------------------------------------------------------
show_help()
{
        echo "${PROGNAME}: -V | -h | [-I {INST1[,INST2...]}]"
        echo "               -V shows script version"
        echo "               -h shows this help"
	echo "               -I defines list of comma separated instance names"
        echo "Ex: ${PROGNAME} "
}

#------------------------------------------------------------------------------
# Verify if the master_curling.sh process is running for an instance
#------------------------------------------------------------------------------
check_instance_master_curling()
{
	l_instance=$1
        ps -ef | grep master_curling.sh | egrep -e "  *-I  *${l_instance}$" | awk 'BEGIN {PID="dummy"} {if ( $3 == 1 ) {PID=$2}} END {print PID}' | read MASTER_CURLING_PID
        if [ ${MASTER_CURLING_PID} = "dummy" ]
	then
		log WARNING "$$ master_curling.sh was not running for instance ${l_instance}. Will restart."
		nohup ${SCRIPT_DIR}/master_curling.sh -I ${l_instance} >/dev/null 2>&1 &
		log INFO "$$ master_curling.sh for instance ${l_instance} was launched with PID: $!"
	else
		log INFO "$$ master_curling.sh was running for instance ${l_instance} with PID ${MASTER_CURLING_PID}"
	fi
}

#------------------------------------------------------------------------------
# parse the arguments using standard getopts function
#------------------------------------------------------------------------------
get_args()
{
	arg_ok="VhI:"
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
			echo ${INSTANCES} | egrep '^[a-zA-Z][a-zA-Z0-9_-]*(,[a-zA-Z][a-zA-Z0-9_-])*$' 1>/dev/null 2>/dev/null
			RES=$?
			if [ "X${RES}" != "X0" ]
			then
				log  "$$ Syntax error - Instances list must be valid instance names separated by commas" >&2
				return 1
			fi
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



# START
PROGNAME=`basename $0`
SCRIPT_DIR=`dirname $0`
VERSION=`echo "$Revision: 1.0.43 $" | cut -f2 -d' '`


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
	echo "Cannot include functions file (${SCRIPT_DIR}/include/functions.sh). Exiting!" >&2
	exit 1
fi

if [ ! -d ${LOG_DIR} ]
then
	log ERROR "$$ Log dir (${LOG_DIR}) does not exist or is not a directory. Exiting"
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


log INFO "Command $0 executed with parameters: $*"
log INFO "SCRIPT DIR = ${SCRIPT_DIR}"
log INFO "Version: ${VERSION}"

if [ "X${INSTANCES_FLAG}" = "X" ]
then
	INSTANCES=`retrieveDefinedInstances`
	if [ $? != 0 ]
	then
		log ERROR "$$ Error on geting list of instances (retrieveDefinedInstances). Exiting!"
		exit 1
	fi
fi

for INSTANCE in ${INSTANCES}
do
	if [ "X${CDC_BLACK_LISTED_INSTANCES}" != "X" ]
	then
		FLAG=0
		for bl_instance in ${CDC_BLACK_LISTED_INSTANCES}
		do
			#check if instance is black listed
			if [ ${INSTANCE} = ${bl_instance} ]
			then
				FLAG=1
			fi
		done
		if [ $FLAG = 1 ]
		then
			log INFO "$$ Skipping instance $instance because it's black listed"
		else
			instanceIsActive ${INSTANCE}
			if [ $? = 0 ]
			then
	                        log INFO "$$ Checking instance ${INSTANCE}"
	                        check_instance_master_curling $INSTANCE
			else
				log INFO "$$ Instance ${INSTANCE} is not running"
			fi
		fi
	else
		instanceIsActive ${INSTANCE}
		if [ $? = 0 ]
		then
			log INFO "$$ Checking instance ${INSTANCE}"
			check_instance_master_curling $INSTANCE
		else
			log INFO "$$ Instance ${INSTANCE} is not running"
		fi
	fi	
done

log INFO "$$ Exiting"
