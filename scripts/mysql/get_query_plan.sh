#!/bin/bash
#
# This file is released under the terms of the Artistic License.
# Please see # the file LICENSE, included in this package, for details.
#
# Copyright (C) 2003-2006 Open Source Development Labs, Inc.
#
# 22 September 2004: Mark Wong
#    Renamed from explain_single_query.sh.in since the file description didn't
#    really match what the scripts was really doing.
#

if [ $# -lt 5 ]; then
        echo "Usage: $0 <scale_factor> <query_name> <output_file> <run dir> <seed file>"
        exit 1
fi

scale_factor=$1
query_name=$2
output_file=$3
RUNDIR=$4
SEED_FILE=$5

query_file="$RUNDIR/$query_name.sql"
tmp_query_file="$RUNDIR/tmp_$query_name.sql"
param_file="$RUNDIR/$query_name.param"

if [ ! -f $SEED_FILE ]; then
	echo "creating seed file $SEED_FILE, you can change the seed by "
	echo "modifying this file"
	./init_seed.sh > $SEED_FILE
fi

# Generate the queries with EXPLAIN to get plans.
rm -f $query_file
${QGEN} -c -r `cat $SEED_FILE` -s $scale_factor -l $param_file $query_name -x > $query_file || exit 1

# modify $query_file so that the commands are in one line
${PARSE_QUERY} $query_file $tmp_query_file E

# Run the queries and save the output.
cat $tmp_query_file | $MYSQL_CLIENT --defaults-file=my.cnf $SID  >> $output_file 2>&1 || exit 1

exit 0
