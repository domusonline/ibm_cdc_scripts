#!/bin/ksh
#------------------------------------------------------------------------------
# Copyright (c) 2017 Fernando Nunes
# License: This script is licensed as Apache ( http://www.apache.org/licenses/LICENSE-2.0.html )
# $Author: Fernando Nunes - domusonline@gmail.com $
# $Revision: 1.0.19 $
# $Date 2017-04-24 18:51:54$
# Disclaimer: This software is provided AS IS, without any kind of guarantee. Use at your own risk.
#------------------------------------------------------------------------------

#------------------------------------------------------------------------------
# clean up aux files
#------------------------------------------------------------------------------
clean_up()
{
	rm -f ${ERR_FILE}
}

#------------------------------------------------------------------------------
# show command syntax
#------------------------------------------------------------------------------

show_help()
{
	echo "${PROGNAME}: -V | -h | [-n number_txs][-l logfile]"
	echo "               -V shows script version"
	echo "               -h shows this help"
	echo "Ex: ${PROGNAME}"
}

#------------------------------------------------------------------------------
# parse the arguments using standard getopts function
#------------------------------------------------------------------------------

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
		*)
			log ERROR "$$ Invalid parameter (${OPTION}) given"
			return 1
			;;
		esac
	done
}


# START
PROGNAME=`basename $0`
SCRIPT_DIR=`dirname $0`
VERSION=`echo "$Revision: 1.0.19 $" | cut -f2 -d' '`

ERR_FILE=/tmp/${PROGNAME}_$$_err
trap clean_up 0


NUM_ARGUMENTS=$#
get_args $*
if [ $? != 0 ]
then
	show_help >&2
	echo "ERROR $$ Invalid parameters Exiting!" >&2
	exit 1
fi

if [ -f ${SCRIPT_DIR}/.oracle_env.sh ]
then
	. ${SCRIPT_DIR}/.oracle_env.sh
fi


sqlplus $ORA_U/$ORA_P 2>${ERR_FILE} <<EOF
set colsep '|'
set echo off
set feedback off
set linesize 200
set pagesize 0
set sqlprompt ''
set trimspool on
set headsep off
set termout off

SELECT
	SUPPLEMENTAL_LOG_DATA_MIN,
	SUPPLEMENTAL_LOG_DATA_PK,
	SUPPLEMENTAL_LOG_DATA_FK,
	SUPPLEMENTAL_LOG_DATA_UI
FROM
	v\$database;
EOF

if [ $? != 0 ]
then
	echo "ERROR: $$ Oracle script raised an error:"
	cat ${ERR_FILE}
	echo "ERROR $$: Exiting!"
	exit 1
fi
