#!/bin/sh
#
# Copyright (C) 2014  Denver Gingerich <denver@ossguy.com>
#
# This file is part of Sopranica.
#
# Sopranica is free software: you can redistribute it and/or modify it under the
# terms of the GNU Affero General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your option) any
# later version.
#
# Sopranica is distributed in the hope that it will be useful, but WITHOUT ANY
# WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
# A PARTICULAR PURPOSE.  See the GNU Affero General Public License for more
# details.
#
# You should have received a copy of the GNU Affero General Public License along
# with Sopranica.  If not, see <http://www.gnu.org/licenses/>.

START_TIMEOUT=10

# TODO: put in common file (also in generate_config.sh)
VINES=vines

# LOGDIR must be relative to the place where vines is run; must not be absolute
LOGDIR=../out_`date -u +%FT%H:%M:%SZ`
mkdir $LOGDIR

$VINES --daemonize --log $LOGDIR/log-vines --pid $LOGDIR/pid start
RV=$?

# start the vines XMPP server
if [ $RV -ne 0 ]
then
	echo "LOG `date +%s.%N`: vines failed to start, with return value $RV"

	$VINES --daemonize --log $LOGDIR/log-vines --pid $LOGDIR/pid stop
	RV=$?

	echo "LOG `date +%s.%N`: stopping vines after start failed returned $RV"

	exit 1
fi
echo "LOG `date +%s.%N`: vines started successfully"

# wait until the vines server is ready before starting tests
COUNT=1
while [ $COUNT -le $START_TIMEOUT ]
do
	grep 'Accepting client connections' $LOGDIR/log-vines > /dev/null
	RV=$?

	if [ $RV -eq 0 ]
	then
		echo "LOG `date +%s.%N`: vines ready after $COUNT attempt(s)"
		break
	fi

	echo "LOG `date +%s.%N`: try $COUNT: vines not ready; grep returned $RV"

	COUNT=`expr $COUNT + 1`
	sleep 1
done

# exit if the vines server was not ready within the allotted timeout
if [ $COUNT -gt $START_TIMEOUT ]
then
	echo "LOG `date +%s.%N`: vines not ready after $START_TIMEOUT seconds"

	$VINES --daemonize --log $LOGDIR/log-vines --pid $LOGDIR/pid stop
	RV=$?

	echo "LOG `date +%s.%N`: vines stop attempt returned $RV"

	exit 2
fi

# run the tests
OLDPWD=`pwd`
cd ..

PASSED=0
FAILED=0

for testcase in `cat test_list`
do
	if [ "`echo $testcase | cut -c1`" = "#" ]
	then
		echo "LOG `date +%s.%N`: skipping commented test - $testcase"
		continue
	fi

	echo "LOG `date +%s.%N`: starting test - $testcase"

	./$testcase $OLDPWD/$LOGDIR $testcase
	RV=$?

	if [ $RV -eq 0 ]
	then
		echo "LOG `date +%s.%N`: $testcase test passed"
		PASSED=`expr $PASSED + 1`
	else
		echo "LOG `date +%s.%N`: $testcase test FAILED, returning $RV"
		FAILED=`expr $FAILED + 1`
	fi
done

TOTAL=`expr $PASSED + $FAILED`
echo "LOG `date +%s.%N`: ran $TOTAL test(s); $PASSED passed, $FAILED failed"

cd $OLDPWD

# stop the vines server since the tests are done
$VINES --daemonize --log $LOGDIR/log-vines --pid $LOGDIR/pid stop
RV=$?

if [ $RV -ne 0 ]
then
	echo "LOG `date +%s.%N`: vines failed to stop, with return value $RV"

	$VINES --daemonize --log $LOGDIR/log-vines --pid $LOGDIR/pid stop
	RV=$?

	echo "LOG `date +%s.%N`: second vines stop attempt returned $RV"

	exit 3
fi

echo "LOG `date +%s.%N`: vines stopped successfully; we're done"

if [ $FAILED -ne 0 ]
then
	# TODO: use mailing list address instead of personal email address

	echo "LOG `date +%s.%N`: $FAILED of $TOTAL test(s) FAILED; fixes needed"
	echo
	echo "LOG `date +%s.%N`: please report this to denver@ossguy.com, plus:"
	echo "ruby version: `ruby --version`"
	echo "vines version: `$VINES --version`"
	echo "uname: `uname -a`"
	echo "lsb_release:"
	lsb_release -a
	echo

	exit 4
fi

echo "LOG `date +%s.%N`: $PASSED of $TOTAL test(s) PASSED; all is well"
