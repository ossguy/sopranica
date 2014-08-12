#!/usr/bin/env ruby
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

require 'blather/client'

from = ARGV[0]
to = ARGV[1]
message = ARGV[2]

setup from + '@sms', 'test123', 'localhost', 25467

when_ready do
	write_to_stream Blather::Stanza::Message.new(to + '@sms', message)
	shutdown
end

Thread.new { EM.run { run } }
