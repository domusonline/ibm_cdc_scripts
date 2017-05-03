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
	echo "               -L number of files in each rm invocation"
	echo "               -d number of days to keep"
        echo "Ex: ${PROGNAME} "
}

#------------------------------------------------------------------------------
# parse the arguments using standard getopts function
#------------------------------------------------------------------------------
get_args()
{
	arg_ok="VhI:L:d:"
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
				echo "${PROGNAME}: Syntax error - Instances list must be valid instance names separated by commas" >&2
				return 1
			fi
			;;
		L)   # set number of files to use in xargs evocation of rm command
			NUM_FILES_FLAG=1
			NUM_FILES=${OPTARG}
			echo ${NUM_FILES} | grep "^[1-9][0-9]*$" >/dev/null
			if [ $? != 0 ]
			then
				log ERROR "$$ option -L must be used with a number"
				return 1
			fi
			;;
		d)   # set number of days to keep
			NUM_DAYS_FLAG=1
			NUM_DAYS=${OPTARG}
			echo ${NUM_DAYS} | grep "^[1-9][0-9]*$" >/dev/null
			if [ $? != 0 ]
			then
				log ERROR "$$ option -d must be used with a number"
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


#------------------------------------------------------------------------------
# Clean up an instance log files
#------------------------------------------------------------------------------
cleanup_instance_logfiles()
{
	l_instance=$1
	INSTANCE_LOG_DIR=`get_instance_dir ${l_instance}`/log

	if [ ! -d ${INSTANCE_LOG_DIR} ]
	then
		log ERROR "$$ Instance log dir (${INSTANCE_LOG_DIR}) doesn't seem to be a directory or is not readable"
		return 1
	fi

	if [ "X${NUM_FILES_FLAG}" = "X" ]
	then
		l_num_files=`eval 'echo $CDC_MAX_NUM_RM_LOGFILES_'${INSTANCE_NAME}`
		if [ "X${l_num_files}" = "X" ]
		then
			l_num_files=`eval 'echo $CDC_MAX_NUM_RM_LOGFILES'`
			if [ "X${l_num_files}" = "X" ]
			then
				l_num_files=${NUM_FILES_SCRIPT_DEFAULT}
			fi
		fi
	else
		l_num_files=${NUM_FILES}
	fi
		
	if [ "X${NUM_DAYS_FLAG}" = "X" ]
	then
		l_num_days=`eval 'echo $CDC_MAX_DAYS_LOGFILES_'${INSTANCE_NAME}`
		if [ "X${l_num_days}" = "X" ]
		then
			l_num_days=`eval 'echo $CDC_MAX_DAYS_LOGFILES'`
			if [ "X${l_num_days}" = "X" ]
			then
				l_num_days=${NUM_DAYS_SCRIPT_DEFAULT}
			fi
		fi
	else
		l_num_days=${NUM_DAYS}
	fi
	
	CD=`pwd`

	cd ${INSTANCE_LOG_DIR}
	CD_AUX=`pwd`
	echo ${CD_AUX} | egrep '^.*\/log$' >/dev/null
	if [ $? != 0 ]
	then
		log ERROR "$$ DANGER: cd to instance log dir didn't work properly: Current dir: ${CD_AUX} Exiting!"
		exit 1
	fi
	find . -regextype ${REGEXP_TYPE} -regex '\.\/trace_dm[a-su-z][a-rt-z][a-z0-9_]*\.log$' -ctime +${l_num_days} | xargs -L ${l_num_files} rm -f
	find . -regextype ${REGEXP_TYPE} -regex '\.\/[0-9][0-9]*.proc$' -ctime +${l_num_days} | xargs -L ${l_num_files} rm -f
	cd ${CD}
	
}

# START
PROGNAME=`basename $0`
SCRIPT_DIR=`dirname $0`
VERSION=`echo "$Revision: 1.0.43 $" | cut -f2 -d' '`


NUM_FILES_SCRIPT_DEFAULT=1000
NUM_DAYS_SCRIPT_DEFAULT=7

SO=`uname -s | tr "[:upper:]" "[:lower:]"`
case $SO in
aix)
	REGEXP_TYPE=Extended
	;;
linux|*)
	REGEXP_TYPE=posix-extended
	;;
esac

# Read the settings from the properties file
if [ -x "${SCRIPT_DIR}/conf/cdc.properties" ]
then
	. "${SCRIPT_DIR}/conf/cdc.properties"
	if [ $? != 0 ]
	then
		echo "$$ ERROR sourcing cdc.properties file. Exiting!"
		exit 1
	fi
else
	echo "Cannot include properties file ("${SCRIPT_DIR}/conf/cdc.properties"). Exiting!"
	exit 1
fi

# Import general functions
if [ -x  "${SCRIPT_DIR}/include/functions.sh" ]
then
	. "${SCRIPT_DIR}/include/functions.sh"
	if [ $? != 0 ]
	then
		echo "$$ ERROR sourcing include/functions.sh file. Exiting!"
		exit 1
	fi
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
			log INFO "$$ Skipping instance ${INSTANCE} because it's black listed"
		else
                        log INFO "$$ Cleaning up instance ${INSTANCE}"
                        cleanup_instance_logfiles $INSTANCE
                fi
        else
		log INFO "$$ Cleaning up instance ${INSTANCE}"
		cleanup_instance_logfiles $INSTANCE
        fi	
done
log INFO "$$ Exiting."
