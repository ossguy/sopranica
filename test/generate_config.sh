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

VINES=vines
HOSTNAME=sms

if [ -e "$HOSTNAME" ]
then
	echo "Cannot setup tests since hostname $HOSTNAME matches existing file"
	exit 1
fi

CONFDIR=$HOSTNAME/conf
CERTDIR=$HOSTNAME/conf/certs
USERDIR=$HOSTNAME/data/user

# TODO: cleanup this list - should be able to specify simply a list of numbers
USER1FILE=$USERDIR/8082061212@$HOSTNAME
USER2FILE=$USERDIR/6026381212@$HOSTNAME
USER3FILE=$USERDIR/6463741212@$HOSTNAME
USER4FILE=$USERDIR/2045151212@$HOSTNAME


mkdir -p $CONFDIR

cat > $CONFDIR/config.rb << THAT_IS_ALL
Vines::Config.configure do
	host '$HOSTNAME' do
		storage 'fs' do
			dir 'data'
		end
	end

	client '0.0.0.0', 25467
end
THAT_IS_ALL


mkdir -p $USERDIR

echo "name: 8082061212" > $USER1FILE
echo "password: `$VINES bcrypt test123`" >> $USER1FILE

echo "name: 6026381212" > $USER2FILE
echo "password: `$VINES bcrypt test123`" >> $USER2FILE

echo "name: 6463741212" > $USER3FILE
echo "password: `$VINES bcrypt test123`" >> $USER3FILE

echo "name: 2045151212" > $USER4FILE
echo "password: `$VINES bcrypt test123`" >> $USER4FILE


mkdir -p $CERTDIR

cd $HOSTNAME
$VINES cert $HOSTNAME
