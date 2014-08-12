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

SMS_RELAY=../sms_relay.rb
SMS_MAPPER=../sms_mapper.rb
SMS_PUBSUB=../sms_relay-pubsub.rb

$SMS_RELAY 16026381212 > $1/$2-relay.log 2>&1 &
$SMS_MAPPER > $1/$2-mapper.log 2>&1 &
$SMS_PUBSUB 18082061212 > $1/$2-pubsub.log 2>&1 &

PIDSFILE=$1/$2-spr_pids
jobs -p > $PIDSFILE

# wait until all three processes are ready before starting tests
COUNT=1
while [ $COUNT -le $START_TIMEOUT ]
do
	grep 'ready to send messages' $1/$2-relay.log > /dev/null
	RV1=$?

	grep 'starting poll' $1/$2-mapper.log > /dev/null
	RV2=$?

	grep 'ready to send messages' $1/$2-pubsub.log > /dev/null
	RV3=$?

	if [ $RV1 -eq 0 ] && [ $RV2 -eq 0 ] && [ $RV3 -eq 0 ]
	then
		echo "LOG `date +%s.%N`: 3 procs ready after $COUNT attempt(s)"
		break
	fi

	echo "LOG `date +%s.%N`: try $COUNT: procs not ready; RV $RV1 $RV2 $RV3"

	COUNT=`expr $COUNT + 1`
	sleep 1
done

# exit if any of the three processes were not ready within the allotted timeout
if [ $COUNT -gt $START_TIMEOUT ]
then
	echo "LOG `date +%s.%N`: 3 procs not ready after $START_TIMEOUT seconds"

	echo "LOG `date +%s.%N`: killing $(echo $(cat $PIDSFILE))"
	for JOB_PID in `cat $PIDSFILE`
	do
		kill -INT $JOB_PID
	done

	exit 2
fi

echo "LOG `date +%s.%N`: about to receive test message"
./util-receive_message.rb 8082061212 6463741212 'test 1a' > $1/$2-receive.log &
echo "LOG `date +%s.%N`: receiver has finished"

# wait until receiver is ready to receive before starting test
COUNT=1
while [ $COUNT -le $START_TIMEOUT ]
do
	grep 'ready to receive' $1/$2-receive.log > /dev/null
	RV=$?

	if [ $RV -eq 0 ]
	then
		echo "LOG `date +%s.%N`: receiver ready after $COUNT attempt(s)"
		break
	fi

	echo "LOG `date +%s.%N`: try $COUNT: receiver not ready; returned $RV"

	COUNT=`expr $COUNT + 1`
	sleep 1
done

# exit if receiver is not ready to receive within the allotted timeout
if [ $COUNT -gt $START_TIMEOUT ]
then
	echo "LOG `date +%s.%N`: receiver not ready in $START_TIMEOUT seconds"

	echo "LOG `date +%s.%N`: killing $(echo $(cat $PIDSFILE))"
	for JOB_PID in `cat $PIDSFILE`
	do
		kill -INT $JOB_PID
	done

	exit 3
fi

echo "LOG `date +%s.%N`: about to send test message"
./util-send_message.rb 2045151212 6026381212 'test 1a'
echo "LOG `date +%s.%N`: test message sent"

# wait until receiver has received or exited
COUNT=1
while [ $COUNT -le $START_TIMEOUT ]
do
	grep 'message received' $1/$2-receive.log > /dev/null
	RV=$?

	if [ $RV -eq 0 ]
	then
		echo "LOG `date +%s.%N`: receiver done after $COUNT attempt(s)"
		break
	fi

	echo "LOG `date +%s.%N`: try $COUNT: receiver not done; returned $RV"

	COUNT=`expr $COUNT + 1`
	sleep 1
done

# exit if receiver has not received or exited within the allotted timeout
if [ $COUNT -gt $START_TIMEOUT ]
then
	echo "LOG `date +%s.%N`: no receiver response in $START_TIMEOUT seconds"

	echo "LOG `date +%s.%N`: killing $(echo $(cat $PIDSFILE))"
	for JOB_PID in `cat $PIDSFILE`
	do
		kill -INT $JOB_PID
	done

	exit 4
fi

grep 'correct message received' $1/$2-receive.log > /dev/null
RV=$?

TEST_RESULT=123

if [ $RV -eq 0 ]
then
	echo "LOG `date +%s.%N`: receiver received the correct message"
	TEST_RESULT=0
else
	echo "LOG `date +%s.%N`: problem with receipt - $RCV_OUTPUT"
	TEST_RESULT=1
fi
	
echo "LOG `date +%s.%N`: take down PIDs $(echo $(cat $PIDSFILE))"
for JOB_PID in `cat $PIDSFILE`
do
	kill -INT $JOB_PID
done

echo "LOG `date +%s.%N`: test completed"

exit $TEST_RESULT
