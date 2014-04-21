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
require 'net/http'
require 'uri'

load 'settings-sms_publisher.rb'	# contains the publishing credentials

puts 'auth id:'
puts AUTH_ID

module SMSPublisher
	def self.log(msg)
		t = Time.now
		log_raw "LOG %d.%09d: %s" % [t.to_i, t.nsec, msg]
	end

	def self.log_raw(msg)
		puts msg
		STDOUT.flush
	end
end

SMSPublisher.log 'starting Sopranica SMS Publisher v0.02'

context = ZMQ::Context.new

monitor = context.socket(ZMQ::PULL)
monitor.connect('ipc://spr-publisher000-monitor')

receiver = context.socket(ZMQ::PULL)
receiver.connect('ipc://spr-publisher000-receiver')

poller = ZMQ::Poller.new
poller.register(monitor, ZMQ::POLLIN)
poller.register(receiver, ZMQ::POLLIN)

trap(:INT) {
	SMSPublisher.log 'application terminating at user request'
	# TODO: add lock? so don't close socket while in middle of processing
	monitor.close
	receiver.close
	context.terminate
	exit
}
# TODO: add TERM handler?

loop do
	SMSPublisher.log 'starting poll...'
	poller.poll(60000)	# block for 60 seconds then process or repeat

	poller.readables.each do |socket|
		if socket === monitor
			#stuff = monitor.recv_string(ZMQ::DONTWAIT)
			monitor.recv_string(stuff = '')
			SMSPublisher.log 'received monitor message: "' + stuff \
				+ '"; ERROR: these are currently unsupported'
		elsif socket === receiver
			#stuff = receiver.recv_string(ZMQ::DONTWAIT)
			receiver.recv_string(stuff = '')
			SMSPublisher.log 'received a message (raw): ' + stuff
			zmq_message = JSON.parse stuff
			SMSPublisher.log 'formatted message: ' \
				+ zmq_message.to_s
			if zmq_message['message_type'] != 'to_other' then
				SMSPublisher.log 'unknown message type: ' \
					+ zmq_message['message_type']
			else
				uri = URI.parse('https://api.plivo.com')
				http = Net::HTTP.new(uri.host, uri.port)
				http.use_ssl = true
				request = Net::HTTP::Post.new(
					'/v1/Account/' + AUTH_ID + '/Message/')
				request.basic_auth AUTH_ID, AUTH_TOKEN
				request.add_field('Content-Type',
					'application/json')
				request.body = JSON.dump({
					'src'	=> zmq_message['user_number'],
					'dst'	=> zmq_message['others_number'],
					'text'	=> zmq_message['body']
				})
				response = http.request(request)
				SMSPublisher.log 'sent message "' \
					+ zmq_message['body'] + '" from ' \
					+ zmq_message['user_number'] + ' to ' \
					+ zmq_message['others_number'] \
					+ '; API response: ' + response.to_s \
					+ 'with body "' + response.body + '"'
				# TODO: do something if the API response is bad
			end
		end
	end
	SMSPublisher.log '...done poll stuff'
end
