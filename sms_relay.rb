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
	puts "Usage: sms_relay.rb <forwarding_number>"
	exit 0
end

fwd_number = ARGV[0]

load "settings-sms_relay-#{fwd_number}.rb"	# has LOGIN_USER and LOGIN_PWD

module SMSRelay
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
		@pusher.bind('ipc://spr-mapper000-receive_relay')

		EM.run { client.run }
	end

	def self.zmq_terminate
		@pusher.close
		@zmq_context.terminate
	end

	setup LOGIN_USER, LOGIN_PWD

	when_ready { log 'ready to send messages; TODO - block send until now' }

	message :chat?, :body do |m|
		user_forward = normalize m.to.node
		user_device = normalize m.from.node

		log 'iMSG - ' + user_device + ' -> ' + user_forward + ': ' \
			+ m.body

		zmq_message = {
			'message_type'	=> 'from_user',
			'user_forward'	=> user_forward,
			'user_device'	=> user_device,
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

SMSRelay.log 'starting Sopranica SMS Relay v0.05'

context = ZMQ::Context.new

monitor = context.socket(ZMQ::PULL)
monitor.connect("ipc://spr-relay#{fwd_number}_000-monitor")

receiver = context.socket(ZMQ::PULL)
receiver.connect("ipc://spr-relay#{fwd_number}_000-receiver")

poller = ZMQ::Poller.new
poller.register(monitor, ZMQ::POLLIN)
poller.register(receiver, ZMQ::POLLIN)

trap(:INT) {
	SMSRelay.log 'application terminating at user INT request'
	# TODO: add lock? so don't close socket while in middle of processing
	receiver.close
	monitor.close
	SMSRelay.zmq_terminate
	EM.stop
	exit
}
# TODO: add TERM handler?

Thread.new { SMSRelay.run(context) }

loop do
	SMSRelay.log 'starting poll...'
	poller.poll(60000)	# block for 60 seconds then process or repeat

	poller.readables.each do |socket|
		if socket === monitor
			monitor.recv_string(stuff = '')
			SMSRelay.log 'received monitor message: "' + stuff \
				+ '"; ERROR: these are currently unsupported'
		elsif socket === receiver
			receiver.recv_string(stuff = '')
			SMSRelay.log 'received a message (raw): ' + stuff
			in_message = JSON.parse stuff
			SMSRelay.log 'formatted message: ' + in_message.to_s
			if in_message['message_type'] == 'to_user' then
				# TODO: handle empty userdev better; no default?
				dst_num = in_message['user_device'].empty? ? \
					DEFAULT_DEV : in_message['user_device']
				# TODO: don't rely on carrier for 140-char split
				msg = Blather::Stanza::Message.new(
					SMSRelay.unnormalize(dst_num) + '@sms',
					in_message['others_number'] + '->' \
						+ in_message['user_number'] \
						+ (in_message['user_device'] \
							.empty? ? ' ERR' : '') \
						+ ' ' + in_message['body']
				)

				SMSRelay.log '>>> sending message ==>'
				SMSRelay.log_raw msg.inspect
				SMSRelay.log '<== end of message to send'

				SMSRelay.log 'oMSG - ' + SMSRelay.jid.node \
					+ ' -> ' + msg.to.node + ': ' + msg.body
				SMSRelay.write_to_stream msg
				SMSRelay.log 'oMSG [sent]'
			else
				SMSRelay.log 'unknown message type: ' \
					+ in_message['message_type']
			end
		end
	end
	SMSRelay.log '...done poll stuff'
end
