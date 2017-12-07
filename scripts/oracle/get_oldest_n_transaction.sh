#!/bin/ksh
#------------------------------------------------------------------------------
# Copyright (c) 2017 Fernando Nunes
# License: This script is licensed as Apache ( http://www.apache.org/licenses/LICENSE-2.0.html )
# $Author: Fernando Nunes - domusonline@gmail.com $
# $Revision: 1.0.56 $
# $Date: 2017-12-07 15:56:45 $
# Disclaimer: This software is provided AS IS, without any kind of guarantee. Use at your own risk.
#------------------------------------------------------------------------------


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
	echo "${PROGNAME}: -V | -h | [-n number_txs][-l logfile]"
	echo "               -V shows script version"
	echo "               -h shows this help"
	echo "               -n number_txs : captures the oldest number_txs open transactions"
	echo "               -l logfile    : saves the transaction(s) in the specificed log file"
	echo "Ex: ${PROGNAME} -n 1 -l last_txs.unl"
}

#------------------------------------------------------------------------------
# parse the arguments using standard getopts function
#------------------------------------------------------------------------------

get_args()
{
	arg_ok="Vhn:l:"
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
		n)      #number of transactions
			TRANSACTIONS_FLAG=1
			TRANSACTIONS=$OPTARG
			echo $TRANSACTIONS | grep "^[0-9][0-9]*$" > /dev/null
			if [ $? != 0 ]
			then
				log ERROR "$$ -n parameter must be supplied with a valid number (${TRANSACTIONS})"
				return 1
			fi
			;;
                l)      #log filename
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
VERSION=`echo "$Revision: 1.0.56 $" | cut -f2 -d' '`


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

NUM_ARGUMENTS=$#
get_args $*
if [ $? != 0 ]
then
	show_help >&2
	log ERROR "$$ Invalid parameters Exiting!"
	exit 1
fi

if [ "X${TRANSACTIONS_FLAG}" = "X" ]
then
	TRANSACTIONS=1
fi

TMP_FILE=/tmp/${PROGNAME}_$$_tmp
ERR_FILE=/tmp/${PROGNAME}_$$_err
trap clean_up 0

if [ "X${LOG_FILE_FLAG}" = "X" ]
then
	SPOOL_CLAUSE=""
else
	log INFO "$$ Command $0 executed with parameters: $*"
	log INFO "$$ SCRIPT DIR = ${SCRIPT_DIR}"
	log INFO "$$ Local file system: ${CDC_HOME_LOCAL_FS}"
	log INFO "$$ Version: ${VERSION}"

	SPOOL_CLAUSE="spool ${TMP_FILE}"
	LOG_FILE=${LOG_DIR}/${LOG_FILE}
	
fi


if [ -f ${SCRIPT_DIR}/.oracle_env.sh ]
then
	. ${SCRIPT_DIR}/.oracle_env.sh
fi

sqlplus -s $ORA_U/$ORA_P 1>${TMP_FILE} 2>${ERR_FILE} <<EOF
set colsep '|'
set echo off
set feedback off
set linesize 2000
set pagesize 0
set sqlprompt ''
set trimspool on
set headsep off
set termout off
$SPOOL_CLAUSE

SELECT
	to_char(SYSDATE,'YYYY-MM-DD HH24:MI:SS'),
	TRIM(CAST((SYSDATE - TO_DATE('1970-01-01', 'YYYY-MM-DD')) * 86400 AS CHAR(12))),
	TO_CHAR(t.start_scn,'99999999999999999'),
	to_char(TO_DATE(t.start_time,'MM/DD/YY HH24:MI:SS'),'YYYY-MM-DD HH24:MI:SS'),
	TRIM(CAST((TO_DATE(t.start_time,'MM/DD/YY HH24:MI:SS') - TO_DATE('1970-01-01', 'YYYY-MM-DD')) * 86400 AS CHAR(12))),
        t.xid,
        t.used_ublk * (select block_size/1024 from dba_tablespaces where tablespace_name like '%UNDO%') size_kb,
	t.used_urec,
        t.status,
	s.sid,
        s.username
FROM
	v\$transaction t INNER JOIN  v\$session s ON (t.ses_addr = s.saddr)
WHERE
	t.xid IN
	(
		SELECT * FROM
		(
			SELECT
				t1.xid AS myxid
			FROM
				v\$transaction t1
			ORDER BY t1.start_time
		)
		WHERE
			ROWNUM <= $TRANSACTIONS
	)
ORDER BY
        t.start_time;
EOF

if [ $? != 0 ]
then
	log ERROR "Oracle script raised an error:"
	promoteLog ${ERR_FILE}
	log ERROR "Exiting!"
	exit 1
fi

if [ "X${LOG_FILE_FLAG}" = "X1" ]
then
	cat ${TMP_FILE} >> ${LOG_FILE}
	log INFO "$$ Exiting"
else
	cat ${TMP_FILE}
fi
