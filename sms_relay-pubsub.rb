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

require 'blather/client/dsl'
require 'ffi-rzmq'
require 'json'

if ARGV.size != 1 then
	puts "Usage: sms_relay-pubsub.rb <forwarding_number>"
	exit 0
end

fwd_number = ARGV[0]

load "settings-sms_relay-pubsub-#{fwd_number}.rb" # has LOGIN_USER and LOGIN_PWD

# use default host and port (implied by the JID) if user didn't define them
LOGIN_HOST = nil unless defined? LOGIN_HOST
LOGIN_PORT = nil unless defined? LOGIN_PORT

module SMSPubSub
	extend Blather::DSL

	def self.log(msg)
		t = Time.now
		log_raw "LOG %d.%09d: %s" % [t.to_i, t.nsec, msg]
	end

	def self.log_raw(msg)
		puts msg
		STDOUT.flush
	end

	def self.normalize(number)
		if number.start_with?('011') then
			return number[3..-1]	# TODO: stylistically, '-1' ugly
		else
			return '1' + number
		end
	end

	def self.unnormalize(number)
		if number.start_with?('1') then
			return number[1..-1]	# TODO: stylistically, '-1' ugly
		else
			return '011' + number
		end
	end

	def self.run(context)
		@zmq_context = context

		@pusher = @zmq_context.socket(ZMQ::PUSH)
		@pusher.bind('ipc://spr-mapper000-receive_accept2')

		EM.run { client.run }
	end

	def self.zmq_terminate
		@pusher.close
		@zmq_context.terminate
	end

	setup LOGIN_USER, LOGIN_PWD, LOGIN_HOST, LOGIN_PORT

	when_ready { log 'ready to send messages; TODO - block send until now' }

	message :chat?, :body do |m|
		others_number = normalize m.from.node
		user_number = normalize m.to.node

		log 'iMSG - ' + others_number + ' -> ' + user_number + ': ' \
			+ m.body

		zmq_message = {
			'message_type'	=> 'from_other',
			'others_number'	=> others_number,
			'user_number'	=> user_number,
			'body'		=> m.body
		}
		@pusher.send_string(JSON.dump zmq_message)

		log 'sent: ' + zmq_message.to_s
	end

	message do |m|
		log "<<< received message stanza ==>"
		log_raw m.inspect
		log "<== end of message stanza"
	end

	presence do |p|
		log "<<< received presence stanza ==>"
		log_raw p.inspect
		log "<== end of presence stanza"
	end

	iq do |i|
		log "<<< received iq stanza ==>"
		log_raw i.inspect
		log "<== end of iq stanza"
	end

	pubsub do |s|
		log "<<< received pubsub stanza ==>"
		log_raw s.inspect
		log "<== end of pubsub stanza"
	end
end

SMSPubSub.log 'starting Sopranica SMS Pub/Sub v0.10'

context = ZMQ::Context.new

monitor = context.socket(ZMQ::PULL)
monitor.connect("ipc://spr-pubsub#{fwd_number}_000-monitor")

receiver = context.socket(ZMQ::PULL)
receiver.connect("ipc://spr-publisher#{fwd_number}_000-receiver")

poller = ZMQ::Poller.new
poller.register(monitor, ZMQ::POLLIN)
poller.register(receiver, ZMQ::POLLIN)

trap(:INT) {
	SMSPubSub.log 'application terminating at user INT request'
	# TODO: add lock? so don't close socket while in middle of processing
	receiver.close
	monitor.close
	SMSPubSub.zmq_terminate
	EM.stop
	exit
}
# TODO: add TERM handler?

Thread.new { SMSPubSub.run(context) }

loop do
	SMSPubSub.log 'starting poll...'
	poller.poll(60000)	# block for 60 seconds then process or repeat

	poller.readables.each do |socket|
		if socket === monitor
			monitor.recv_string(stuff = '')
			SMSPubSub.log 'received monitor message: "' + stuff \
				+ '"; ERROR: these are currently unsupported'
		elsif socket === receiver
			receiver.recv_string(stuff = '')
			SMSPubSub.log 'received a message (raw): ' + stuff
			in_message = JSON.parse stuff
			SMSPubSub.log 'formatted message: ' + in_message.to_s
			if in_message['message_type'] == 'to_other' then
				# TODO: don't rely on carrier for 140-char split
				# TODO: ensure in_msg user_number == fwd_number
				msg = Blather::Stanza::Message.new(
					SMSPubSub.unnormalize(
						in_message['others_number']
					) + '@sms',
					in_message['body']
				)

				SMSPubSub.log '>>> sending message ==>'
				SMSPubSub.log_raw msg.inspect
				SMSPubSub.log '<== end of message to send'

				SMSPubSub.log 'oMSG - ' + SMSPubSub.jid.node \
					+ ' -> ' + msg.to.node + ': ' + msg.body
				SMSPubSub.write_to_stream msg
				SMSPubSub.log 'oMSG [sent]'

				# add a delay because some recipients drop
				#  messages when sent too fast; some results:
				#  * 1.0 is fine (over ~50 msgs) but is too slow
				#  * 0.1 is ok (1 lost over ~100 msgs)
				#  * 0.01 is ok (1 lost over ~50 msgs)
				# TODO: find way to guarantee receipt w/o delay
				delay_seconds = 0.1
				SMSPubSub.log 'delay the next poll by ' \
					+ delay_seconds.to_s \
					+ 's to ensure receiver not overloaded'
				sleep delay_seconds
			else
				SMSPubSub.log 'unknown message type: ' \
					+ in_message['message_type']
			end
		end
	end
	SMSPubSub.log '...done poll stuff'
end
