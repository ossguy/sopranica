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

require 'ffi-rzmq'
require 'json'
require 'sinatra'

load 'settings-sms_acceptor.rb'	# has (TODO: add stuff that it has)

set :bind, '0.0.0.0'
set :port, 23470

module SMSAcceptor
	def self.log(msg)
		t = Time.now
		puts "LOG %d.%09d: %s" % [t.to_i, t.nsec, msg]
	end

	def self.log_raw(msg)
		puts msg
	end
end

SMSAcceptor.log 'starting Sopranica SMS Acceptor v0.01'

context = ZMQ::Context.new

monitor = context.socket(ZMQ::PULL)
monitor.connect('ipc://spr-acceptor000-monitor')

mapper = context.socket(ZMQ::PUSH)
mapper.bind('ipc://spr-mapper000-receiver')

poller = ZMQ::Poller.new
poller.register(monitor, ZMQ::POLLIN)

# TODO; somehow actual poll the poller (while listening to POSTs, too)

trap(:INT) {
        SMSAcceptor.log 'application terminating at user INT request'
        # TODO: add lock? so don't close socket while in middle of processing
        monitor.close
        mapper.close
        context.terminate
        exit
}
# TODO: add TERM handler?

post '/' do
	SMSAcceptor.log 'received a POST with the following data:'
	# TODO: pass param[:To], :From, and :Text to mapper (use right msg type)
	params.each do |param, value|
		SMSAcceptor.log "	#{param}: #{value}"
	end
	return 'ok'
end
