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

# TODO: MUST enforce at <fwd>,<usernum> validation/insertion time that:
# * for each device in USERNUM_TO_DEVICES[<usernum>] that:
# ** for each other_usernum in DEVICE_TO_USERNUMS[<device>]:
# *** there is no FWD_TO_OTHER[<fwd>, <other_usernum>] in existence
# * only if there are no matches in all above iterations can we add the mapping
# Obviously, also confirm that the <other>,<usernum> and <fwd>,<usernum> pairs
# do not exist.  With the above, we can guarantee that when going through the
# list of <usernum>s for a given device, that the first <fwd>,<usernum> will be
# the right one (ie. this is the only match; it is unambiguously the right one).
# This is while searching the list when we receive SMS from one of the devices.

FWD_AND_USERNUM_TO_OTHER = {}
OTHER_AND_USERNUM_TO_FWD.each do |other_and_usernum, fwdnum|
	FWD_AND_USERNUM_TO_OTHER[  [fwdnum, other_and_usernum[1] ]  ] =
		other_and_usernum[0]
end

DEVICE_TO_USERNUMS = {}
USERNUM_TO_DEVICES.each do |usernum, devices|
	devices.each do |device|
		if DEVICE_TO_USERNUMS[device] then
			DEVICE_TO_USERNUMS[device].push(usernum)
		else
			DEVICE_TO_USERNUMS[device] = [ usernum ]
		end
	end
end

module SMSMapper
	def self.log(msg)
		t = Time.now
		log_raw "LOG %d.%09d: %s" % [t.to_i, t.nsec, msg]
	end

	def self.log_raw(msg)
		puts msg
		STDOUT.flush
	end
end

SMSMapper.log 'starting Sopranica SMS Mapper v0.04'

context = ZMQ::Context.new

monitor = context.socket(ZMQ::PULL)
monitor.connect('ipc://spr-mapper000-monitor')

receive_accept = context.socket(ZMQ::PULL)
receive_accept.connect('ipc://spr-mapper000-receive_accept')

receive_relays = []
# ugly to iterate this list again, but better not to make new one we don't use
OTHER_AND_USERNUM_TO_FWD.each do |other_and_usernum, fwdnum|
	receive_relay = context.socket(ZMQ::PULL)
	receive_relay.connect('ipc://spr-mapper000-receive_relay' + fwdnum)
	receive_relays.push(receive_relay)
end

publisher = context.socket(ZMQ::PUSH)
publisher.bind('ipc://spr-publisher000-receiver')

poller = ZMQ::Poller.new
poller.register(monitor, ZMQ::POLLIN)
poller.register(receive_accept, ZMQ::POLLIN)

receive_relays.each do |receive_relay|
	poller.register(receive_relay, ZMQ::POLLIN)
end

trap(:INT) {
	SMSMapper.log 'application terminating at user request'
	# TODO: add lock? so don't close socket while in middle of processing
	monitor.close
	receive_accept.close
	receive_relays.each do |receive_relay|
		receive_relay.close
	end
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
		else
			# TODO: check if socket in receive_relays or
			#  socket === receive_accept (so we know it's expected)
			#stuff = receiver.recv_string(ZMQ::DONTWAIT)
			socket.recv_string(stuff = '')
			SMSMapper.log 'received a message (raw): ' + stuff
			in_message = JSON.parse stuff
			SMSMapper.log 'formatted message: ' + in_message.to_s
			if in_message['message_type'] == 'from_user' then
				# TODO: do something smart if mapping not found
				DEVICE_TO_USERNUMS[ in_message['user_device'] ].
					each do |usernum|

					othersnum = FWD_AND_USERNUM_TO_OTHER[ [
						in_message['user_forward'],
						usernum
					] ]

					if othersnum.nil? then
						next
					end

					out_message = {
						'message_type'	=> 'to_other',
						'others_number'	=> othersnum,
						'user_number'	=> usernum,
						'body'		=>
							in_message['body']
					}
					publisher.send_string(
						JSON.dump out_message)
					SMSMapper.log(
						'sent message to publish: ' \
						+ out_message.to_s)
					break
				end
			elsif in_message['message_type'] == 'from_other' then
				fwdnum = OTHER_AND_USERNUM_TO_FWD[ [
					in_message['others_number'],
					in_message['user_number']
				] ]

				if fwdnum.nil? then
					fwdnum = DEFAULT_FWD
					SMSMapper.log 'using default: ' + fwdnum
				end

				SMSMapper.log(
					'sending out message using fwdnum: ' \
					+ fwdnum)

				# don't worry: user forward # is in relay addr
				# TODO: do actual right thing when mapping nil

				relay = context.socket(ZMQ::PUSH)
				relay.bind('ipc://spr-relay' + fwdnum \
					+ '_000-receiver')

				USERNUM_TO_DEVICES[ in_message['user_number'] ].
					each do |device|

					# TODO stop whitespace cheat; move2 func
					out_message = {
						'message_type'	=> 'to_user',
						'others_number'	=>
						    in_message['others_number'],
						'user_number'	=>
						    in_message['user_number'],
						'user_device'	=> device,
						'body'		=>
						    in_message['body']
					}

					relay.send_string(JSON.dump out_message)
					SMSMapper.log(
						'sent message to give user: ' \
						+ out_message.to_s)
				end
				relay.close
			else
				SMSMapper.log 'unknown message type: ' \
					+ in_message['message_type']
			end
		end
	end
	SMSMapper.log '...done poll stuff'
end
