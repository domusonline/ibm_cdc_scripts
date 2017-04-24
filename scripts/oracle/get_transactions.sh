#!/bin/ksh
#---------------------------------------------------------------------------------------------------
# Copyright (c) 2017 Fernando Nunes
# Based on previous script by Frank Ketelaars and Robert Philo
# License: This script is licensed as Apache ( http://www.apache.org/licenses/LICENSE-2.0.html )
# $Author: Fernando Nunes - domusonline@gmail.com $
# $Revision: 1.0.12 $
# $Date 2017-04-24 15:58:50$
# Disclaimer: This software is provided AS IS, without any kind of guarantee. Use at your own risk.
#---------------------------------------------------------------------------------------------------


#------------------------------------------------------------------------------
# clean up...
#------------------------------------------------------------------------------
clean_up()
{
	rm -f ${TMP_FILE} ${ERR_FILE}
}

#------------------------------------------------------------------------------
# show command syntax
#------------------------------------------------------------------------------
show_help()
{
        echo "${PROGNAME}: -V | -h | [-l log_file] -s size"
        echo "               -V shows script version"
        echo "               -h shows this help"
	echo "               -l log_file (log filename to use)"
        echo "               -s size (minimum size in KB of UNDO to report)"
        echo "Ex: ${PROGNAME} -s 500"
}

#------------------------------------------------------------------------------
# parse the arguments using standard getopts function
#------------------------------------------------------------------------------
get_args()
{
	arg_ok="Vhs:l:"
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
		s)	#transaction size
			SIZE_FLAG=1
			SIZE=$OPTARG
			echo $SIZE | grep "^[0-9][0-9]*$" > /dev/null
			if [ $? != 0 ]
			then
				log ERROR "$$ -s parameter must be supplied with a valid number (${SIZE})"
				return 1
			fi
			;;
		l)	#log filename
			LOG_FILE_FLAG=1
			LOG_FILE=${OPTARG}
			echo ${LOG_FILE} | grep "/" > /dev/null
			if [ $? = 0 ]
			then
				log ERROR "$$ Log filename (${LOG_FILE}) must not contain directories"
				return 1
			fi
			;;
		*)
			log ERROR "$$ Invalid parameter (${OPTION}) given"
			return 1
			;;
		esac
	done
	return 0
}



# START
PROGNAME=`basename $0`
SCRIPT_DIR=`dirname $0`
VERSION=`echo "$Revision: 1.0.12 $" | cut -f2 -d' '`


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
	echo "Cannot include functions file (${SCRIPT_DIR}/include/functions.sh). Exiting!"
	exit 1
fi

log INFO "$$ Command $0 executed with parameters: $*"
log INFO "$$ SCRIPT DIR = ${SCRIPT_DIR}"
log INFO "$$ Local file system: ${CDC_HOME_LOCAL_FS}"
log INFO "$$ Version: ${VERSION}"

NUM_ARGUMENTS=$#
get_args $*
if [ $? != 0 ]
then
	show_help >&2
	log INFO "$$ Exiting!"
	exit 1
fi


if [ "X${SIZE_FLAG}" != "X1" ]
then
	log ERROR "$$ Size (-s parameter) not provided. Exiting!"
	exit 1
fi

if [ "X${LOG_DIR}" = "X" ]
then
	log ERROR "$$ Log dir is not defined. Exiting!"
	exit 1
fi

if [ ! -d ${LOG_DIR} ]
then
	log ERROR "$$ Log dir (${LOG_DIR}) does not exist or is not a directory. Exiting"
	exit 1
fi

if [ "X${LOG_FILE_FLAG}" = "X1" ]
then
	LOG_FILE=${LOG_DIR}/${LOG_FILE}
else
	LOG_FILE=${LOG_DIR}/open_txs.unl
fi

TMP_FILE=/tmp/${PROGNAME}_$$_.tmp
ERR_FILE=/tmp/${PROGNAME}_$$_.err
trap clean_up 0

if [ -f ${SCRIPT_DIR}/.oracle_env.sh ]
then
	. ${SCRIPT_DIR}/.oracle_env.sh
fi

sqlplus -s $ORA_U/$ORA_P 1>/dev/null 2>${ERR_FILE} <<EOF
set colsep '|'
set echo off
set feedback off
set linesize 32000
set pagesize 0
set sqlprompt ''
set trimspool on
set headsep off
set termout off
spool $TMP_FILE

SELECT
	to_char(SYSDATE,'YYYY-MM-DD HH24:MI:SS'),
	t.start_scnw,t.start_scnb,
	to_char(TO_DATE(t.start_time,'MM/DD/YY HH24:MI:SS'),'YYYY-MM-DD HH24:MI:SS'),
	t.xid,
	t.used_ublk * (select block_size/1024 from dba_tablespaces where tablespace_name like '%UNDO%') size_kb,
	t.used_urec,
	SUBSTR(o.owner,1,20) o_owner,
	SUBSTR(o.object_name,1,32) oname,
	t.status,
	s.sid,
	TRIM(s.username),
	TRIM(s.osuser),
	TRIM(s.machine),
	TRIM(s.program),
	TRIM(
		CAST(
			SUBSTR(s1.sql_text,1,4000) AS VARCHAR2(4000)
		)
	)
FROM
	v\$transaction t INNER JOIN  v\$session s ON( t.ses_addr = s.saddr)
	INNER JOIN v\$locked_object l ON ( s.sid = l.session_id)
	INNER JOIN dba_objects o ON (l.object_id = o.object_id)
	LEFT OUTER JOIN dba_hist_sqltext s1 ON (s.sql_id = s1.sql_id)
WHERE
	o.owner NOT IN ('SYS') AND
	t.used_ublk * (select block_size/1024 from dba_tablespaces where tablespace_name like '%UNDO%') > $SIZE
ORDER BY
	t.xid, oname;
EOF

if [ $? = 0 ]
then
	cat $TMP_FILE >> $LOG_FILE
else
	promoteLog $ERR_FILE
fi
log INFO "$$ Exiting"
