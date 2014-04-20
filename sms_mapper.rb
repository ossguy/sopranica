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

load 'settings-sms_mapper.rb'	# has all the mappings (for now)

module SMSMapper
	def self.log(msg)
		t = Time.now
		puts "LOG %d.%09d: %s" % [t.to_i, t.nsec, msg]
	end

	def self.log_raw(msg)
		puts msg
	end
end

SMSMapper.log 'starting Sopranica SMS Mapper v0.02'

context = ZMQ::Context.new

monitor = context.socket(ZMQ::PULL)
monitor.connect('ipc://spr-mapper000-monitor')

receiver = context.socket(ZMQ::PULL)
receiver.connect('ipc://spr-mapper000-receiver')

publisher = context.socket(ZMQ::PUSH)
publisher.bind('ipc://spr-publisher000-receiver')

poller = ZMQ::Poller.new
poller.register(monitor, ZMQ::POLLIN)
poller.register(receiver, ZMQ::POLLIN)

trap(:INT) {
	SMSMapper.log 'application terminating at user request'
	# TODO: add lock? so don't close socket while in middle of processing
	monitor.close
	receiver.close
	publisher.close
	context.terminate
	exit
}
# TODO: add TERM handler?

loop do
	SMSMapper.log 'starting poll...'
	poller.poll(60000)	# block for 60 seconds then process or repeat

	poller.readables.each do |socket|
		if socket === monitor
			#stuff = monitor.recv_string(ZMQ::DONTWAIT)
			monitor.recv_string(stuff = '')
			SMSMapper.log 'received monitor message: "' + stuff \
				+ '"; ERROR: these are currently unsupported'
		elsif socket === receiver
			#stuff = receiver.recv_string(ZMQ::DONTWAIT)
			receiver.recv_string(stuff = '')
			SMSMapper.log 'received a message (raw): ' + stuff
			in_message = JSON.parse stuff
			SMSMapper.log 'formatted message: ' + in_message.to_s
			if in_message['message_type'] == 'from_user' then
				# TODO: do something smart if mapping not found
				other_and_user = USER_TO_OTHER[ [
					in_message['user_forward'],
					in_message['user_device']
				] ]
				out_message = {
					'message_type'	=> 'to_other',
					'others_number'	=> other_and_user[0],
					'user_number'	=> other_and_user[1],
					'body'		=> in_message['body']
				}
				publisher.send_string(JSON.dump out_message)
				SMSMapper.log 'sent message to publish: ' \
					+ out_message.to_s
			elsif in_message['message_type'] == 'from_other' then
				fwd_and_device = OTHER_TO_USER[ [
					in_message['others_number'],
					in_message['user_number']
				] ]

				# don't worry: user forward # is in relay addr
				# TODO: do actual right thing when mapping nil
				out_message = {
					'message_type'	=> 'to_user',
					'others_number'	=>
						in_message['others_number'],
					'user_number'	=>
						in_message['user_number'],
					'user_device'	=>
						fwd_and_device.nil? ? '' \
							: fwd_and_device[1],
					'body'		=>
						in_message['body']
				}

				relay = context.socket(ZMQ::PUSH)
				relay.bind('ipc://spr-relay' \
					+ (fwd_and_device.nil? ? DEFAULT_FWD \
						: fwd_and_device[0]) \
					+ '_000-receiver')
				relay.send_string(JSON.dump out_message)
				relay.close
				SMSMapper.log 'sent message to give user: ' \
					+ out_message.to_s
			else
				SMSMapper.log 'unknown message type: ' \
					+ in_message['message_type']
			end
		end
	end
	SMSMapper.log '...done poll stuff'
end
