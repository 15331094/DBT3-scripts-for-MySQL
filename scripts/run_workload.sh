#!/bin/bash
#
# This file is released under the terms of the Artistic License.
# Please see the file LICENSE, included in this package, for details.
#
# Copyright (C) 2004-2006 Mark Wong & Jenny Zhang
#                    Open Source Development Labs, Inc.
#

usage()
{
	echo "usage: run_workload.sh [-123eghouz] [-c comment] [-d data dir]"
	echo "  [-f scale factor] [-l database port] [-n streams]"
	echo "  [-p load test database parameters]"
	echo "  [-q power test database parameters]"
	echo "  [-r throughput test database parameters]"
	echo "  [-s seed]"
	echo ""
	echo " 1 - run load test"
	echo " 2 - run power test"
	echo " 3 - run throughput test"
	echo " c - comment about the test"
	echo " d - database directory"
	echo " e - EXPLAIN ANALYZE (PostgreSQL only)"
	echo " g - generate flat files"
	echo " h - this help message"
	echo " l - database port"
	echo " n - number of throughput streams"
	echo " o - enable oprofile"
	echo " p - database parameters for the load test"
	echo " q - database parameters for the power test"
	echo " r - database parameters for the throughput test"
	echo " s - seed"
	echo " u - use tablespaces"
	echo " z - do not run refresh streams"
}

SRCDIR=/root/benchmark/dbt3-ingres
DATABASE=
SCRIPTDIR=$SRCDIR/scripts
DBSCRIPTDIR=$SRCDIR/scripts/$DATABASE

DIR=`dirname $0`
source ${DIR}/dbt3_profile || exit 1

SEED=0
REDIR_LOG=0
REDIR_TMP=0
SCALE_FACTOR=1
STREAMS=1
MAX=1
GENERATE=0
TEST_ARGS=
DBDATA=${DSS_PATH}

COMMENT=""
RUN_ALL_TESTS=1
RUN_LOAD_TEST=0
RUN_POWER_TEST=0
RUN_THROUGHPUT_TEST=0
FLAG_POWER_TEST=""
FLAG_THROUGHPUT_TEST=""
while getopts "123d:c:ef:ghl:n:op:q:r:s:tuz" opt; do
	case $opt in
	1)
		RUN_LOAD_TEST=1
		RUN_ALL_TESTS=0
		;;
	2)
		RUN_POWER_TEST=1
		FLAG_POWER_TEST="-2"
		RUN_ALL_TESTS=0
		;;
	3)
		RUN_THROUGHPUT_TEST=1
		FLAG_THROUGHPUT_TEST="-3"
		RUN_ALL_TESTS=0
		;;
	c)
		COMMENT=${OPTARG}
		;;
	d)
		DBDATA=${OPTARG}
		;;
	e)
		# PostgreSQL only: EXPLAIN ANALIZE.
		TEST_ARGS="$TEST_ARGS -e"
		;;
	f)
		SCALE_FACTOR=$OPTARG
		echo "SCALE: $SCALE_FACTOR"
		;;
	g)
		GENERATE=1
		;;
	h)
		usage
		exit 1
		;;
	l)
		DBPORT=$OPTARG
		;;
	n)
		STREAMS=$OPTARG
		;;
	o)
		OPROFILE_FLAG="-y"
		;;
	p)
		# PostgreSQL only.
		LOAD_PARAMETERS="${DEFAULT_LOAD_PARAMETERS} $OPTARG"
		;;
	q)
		# PostgreSQL only.
		POWER_PARAMETERS="${DEFAULT_POWER_PARAMETERS} $OPTARG"
		;;
	r)
		# PostgreSQL only.
		THROUGHPUT_PARAMETERS="${DEFAULT_THROUGHPUT_PARAMETERS} $OPTARG"
		;;
	s)
		SEED=$OPTARG
		;;
	u)
		TABLESPACES_FLAG="-t"
		;;
	z)
		NO_REFRESH_FLAG="-z"
		;;
	esac
done

#
# Reset the flags based to make the logic later in the script easier.
#
if [ ${RUN_ALL_TESTS} -eq 1 ]; then
	RUN_LOAD_TEST=1
	RUN_POWER_TEST=1
	RUN_THROUGHPUT_TEST=1
	FLAG_POWER_TEST="-2"
	FLAG_THROUGHPUT_TEST="-3"
fi

# Determine a unique identifer for this test run.
RUN_NUMBER=-1
if test -f run_number; then
	read RUN_NUMBER < run_number
fi
if [ $RUN_NUMBER -eq -1 ]; then
	RUN_NUMBER=0;
fi

# Create output directories.
OUTPUT_DIR=$SRCDIR/scripts/output/$RUN_NUMBER
mkdir -p $OUTPUT_DIR



if [ "x${COMMENT}" != "x" ]; then
	echo ${COMMENT} > ${OUTPUT_DIR}/comment.txt
fi

# Set the seed file.
SEED_FILE=$OUTPUT_DIR/seed
if [ $SEED -eq 0 ]; then
	$SRCDIR/scripts/init_seed.sh > $SEED_FILE
else
	echo $SEED > $SEED_FILE
fi
echo "Using seed: `cat $SEED_FILE`"

#
# Load Test
#
if [ ${RUN_LOAD_TEST} -eq 1 ]; then
	$DBSCRIPTDIR/load_test.sh \
			-o $OUTPUT_DIR/load \
			-z ${DBPORT} \
			-p "${LOAD_PARAMETERS}" \
			${OPROFILE_FLAG} \
			-f $SCALE_FACTOR \
			-g $GENERATE \
			-d ${DBDATA} \
			${TABLESPACES_FLAG} || exit 1
else
	#
	# If the load test wasn't performed the time statistics needs to
	# be cleared out.  Otherwise the data collection will be
	# incomprehensible with duplicate data.
	#
	${DBSCRIPTDIR}/start_db.sh -p "-c port=${DBPORT}"
	${DBSCRIPTDIR}/clear-time-statistics.sh ${DBPORT} || exit 1
fi

i=1
while [ $i -le $MAX ]
do
	#
	# Start time of a Power and Throughput test.
	#
	s_time=`$GTIME`
	${DBSCRIPTDIR}/record_start.sh -l ${DBPORT} -n "PERF${i}" || exit 1

	if [ ${RUN_POWER_TEST} -eq 1 ]; then
		#
		# Power Test
		#
		${DBSCRIPTDIR}/power_test.sh \
				-f ${SCALE_FACTOR} \
				-o ${OUTPUT_DIR}/power${i} \
				-p "${POWER_PARAMETERS}" ${TEST_ARGS} \
				-s ${SEED_FILE} \
				-t ${i} ${OPROFILE_FLAG} ${NO_REFRESH_FLAG}
		if [ $? -eq 1 ] ; then 
			echo "power_test problem!"
			exit 1  
		fi
	fi

	if [ ${RUN_THROUGHPUT_TEST} -eq 1 ]; then
	#
	# Throughput Test
	#
		${DBSCRIPTDIR}/throughput_test.sh \
				-l ${DBPORT} \
				-n ${STREAMS} \
				-f ${SCALE_FACTOR} \
				-o ${OUTPUT_DIR}/throughput${i} \
				-p "${THROUGHPUT_PARAMETERS}" ${TEST_ARGS} \
				-s ${SEED_FILE} \
				-t $i ${OPROFILE_FLAG} ${NO_REFRESH_FLAG} 
		if [ $? -eq 1 ] ; then 
			echo "throughput_test problem!"
			exit 1  
		fi
	fi

	#
	# The database should be shut down after the last test, so start it back
	# up so we can update and retrieve test information in the database.
	#
	${DBSCRIPTDIR}/start_db.sh -p "-c port=${DBPORT}"

	#
	# End time of a Power and Throughput test.
	#
	$DBSCRIPTDIR/record_end.sh -l ${DBPORT} -n "PERF${i}" || exit 1
	e_time=`$GTIME`
	diff_time=`expr $e_time - $s_time`
	echo "Elapsed time for performance test ${i} : $diff_time seconds"

	#
	# Increment loop counter.
	#
	i=`expr $i + 1`
done

# Get system details.
$SCRIPTDIR/get_config.sh $SCALE_FACTOR $STREAMS "$LOAD_PARAMETERS" "$POWER_PARAMETERS" "$THROUGHPUT_PARAMETERS" $OUTPUT_DIR || exit 1

# Get query times.
${DBSCRIPTDIR}/q_time.sh -l ${DBPORT} > ${OUTPUT_DIR}/q_time.out || exit 1

#
# Calculate composite score.      
#
if [ ${RUN_POWER_TEST} -eq 1 ] || [ ${RUN_THROUGHPUT_TEST} -eq 1 ]; then
	$SRCDIR/scripts/get_composite.sh \
			-i ${OUTPUT_DIR}/q_time.out \
			-p 1 \
			-s ${SCALE_FACTOR} \
			-n ${STREAMS} \
			-o ${OUTPUT_DIR}/calc_composite.out \
			${NO_REFRESH_FLAG} \
			${FLAG_POWER_TEST} ${FLAG_THROUGHPUT_TEST} || exit 1
	${DBSCRIPTDIR}/graph_query_time.pl \
			--if $OUTPUT_DIR/q_time.out ${NO_REFRESH_FLAG} \
			${FLAG_POWER_TEST} ${FLAG_THROUGHPUT_TEST} || exit 1
fi
$SRCDIR/scripts/gen_html.sh $OUTPUT_DIR > $OUTPUT_DIR/index.html || exit 1

#
# Stop the database at the end of the test.
#
$DBSCRIPTDIR/stop_db.sh

RUN_NUMBER=`expr $RUN_NUMBER + 1`
echo $RUN_NUMBER > run_number

echo "Results are in $OUTPUT_DIR"

exit 0
