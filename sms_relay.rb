#!/usr/bin/env ruby
#
# Copyright (C) 2014-2015  Denver Gingerich <denver@ossguy.com>
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

# use default host and port (implied by the JID) if user didn't define them
LOGIN_HOST = nil unless defined? LOGIN_HOST
LOGIN_PORT = nil unless defined? LOGIN_PORT

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

	def self.run(context, fwd_number)
		@last_iq_id = ''
		@last_reply_address = ''
		@zmq_context = context

		@pusher = @zmq_context.socket(ZMQ::PUSH)
		@pusher.bind('ipc://spr-mapper000-receive_relay' + fwd_number)

		EM.run { client.run }
	end

	def self.set_last_iq_id(iq_id)
		if not @last_iq_id.empty? then
			log 'WARNING: last iq id is non-empty (' + @last_iq_id +
				'); pings too frequent or server not responding'
		end

		log 'setting last iq id to ' + iq_id
		@last_iq_id = iq_id
	end

	def self.set_last_reply_address(reply_address)
		if not @last_reply_address.empty? then
			log 'WARNING: last reply address is non-empty (' +
				@last_reply_address +
				'); pings too frequent or server not responding'
		end

		log 'setting last reply address to ' + reply_address
		@last_reply_address = reply_address
	end

	def self.zmq_terminate
		@pusher.close
		@zmq_context.terminate
	end

	setup LOGIN_USER, LOGIN_PWD, LOGIN_HOST, LOGIN_PORT

	when_ready { log 'ready to send messages; TODO - block send until now' }

	disconnected {
		log 'disconnected; reconnecting now...'
		client.connect
	}

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

		if i.id == @last_iq_id then
			log 'last iq id (' + @last_iq_id +
				") matches this message's id (" + i.id +
				') so replying to ' + @last_reply_address

			out_message = {
				'type_requested'	=> 'ping',
				'services_up'		=> 'all',
				'reply_address'		=> @last_reply_address,
				'iq_id'			=> i.id
			}

			log 'sending ' + out_message.to_s
			inquisitor = @zmq_context.socket(ZMQ::PUSH)
			inquisitor.bind('ipc://' + @last_reply_address)
			inquisitor.send_string(JSON.dump out_message)
			inquisitor.close
			log 'message sent to ' + @last_reply_address

			@last_iq_id = ''
			@last_reply_address = ''
		else
			log 'WARNING: last iq id (' + @last_iq_id +
				") does not match this message's id (" + i.id +
				') so not replying to ' + @last_reply_address
		end
	end

	pubsub do |s|
		log "<<< received pubsub stanza ==>"
		log_raw s.inspect
		log "<== end of pubsub stanza"
	end
end

SMSRelay.log 'starting Sopranica SMS Relay v0.13'

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

Thread.new { SMSRelay.run(context, fwd_number) }

loop do
	SMSRelay.log 'starting poll...'
	poller.poll(60000)	# block for 60 seconds then process or repeat

	poller.readables.each do |socket|
		if socket === monitor
			monitor.recv_string(stuff = '')
			SMSRelay.log 'received monitor message: "' + stuff + '"'

			in_message = JSON.parse stuff
			SMSRelay.log 'formatted message: ' + in_message.to_s

			if 'ping' == in_message['type_requested'] then
				SMSRelay.log 'processing ping request'
			else
				SMSRelay.log 'unsupported requested type: "' +
					in_message['type_requested']
				next
			end

			out_message = {
				'type_requested'=> 'ping',
				'services_up'	=> 'rpc',
				'reply_address'	=> in_message['reply_address']
			}

			SMSRelay.log 'sending ping reply 1: ' + out_message.to_s
			inquisitor = context.socket(ZMQ::PUSH)
			inquisitor.bind('ipc://' + in_message['reply_address'])
			inquisitor.send_string(JSON.dump out_message)
			SMSRelay.log 'sent to ' + in_message['reply_address']

			msg = Blather::Stanza::Iq::Ping.new(:get, 's.ms')

			SMSRelay.set_last_iq_id(msg.id)
			SMSRelay.set_last_reply_address(
				in_message['reply_address'])

			SMSRelay.log '>>> sending ping message ==>'
			SMSRelay.log_raw msg.inspect
			SMSRelay.log '<== end of message to send'

			SMSRelay.log 'oMSG - ' + SMSRelay.jid.node + ': ' +
				msg.to_s
			SMSRelay.write_to_stream msg
			SMSRelay.log 'oMSG [sent]'

			# keep out_message the same, but replace services_up val
			out_message['services_up'] = 'xmpp_send'

			SMSRelay.log 'sending ping reply 2: ' + out_message.to_s
			inquisitor.send_string(JSON.dump out_message)
			inquisitor.close
			SMSRelay.log 'sent to ' + in_message['reply_address']

		elsif socket === receiver
			receiver.recv_string(stuff = '')
			SMSRelay.log 'received a message (raw): ' + stuff
			in_message = JSON.parse stuff
			SMSRelay.log 'formatted message: ' + in_message.to_s
			if in_message['message_type'] == 'to_user' then
				# TODO: don't rely on carrier for 140-char split
				msg = Blather::Stanza::Message.new(
					SMSRelay.unnormalize(
						in_message['user_device']
					) + '@sms',
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

				# add a delay because some recipients drop
				#  messages when sent too fast; some results:
				#  * 1.0 is fine (over ~50 msgs) but is too slow
				#  * 0.1 is ok (1 lost over ~100 msgs)
				#  * 0.01 is ok (1 lost over ~50 msgs)
				# TODO: find way to guarantee receipt w/o delay
				delay_seconds = 0.1
				SMSRelay.log 'delay the next poll by ' \
					+ delay_seconds.to_s \
					+ 's to ensure receiver not overloaded'
				sleep delay_seconds
			else
				SMSRelay.log 'unknown message type: ' \
					+ in_message['message_type']
			end
		end
	end
	SMSRelay.log '...done poll stuff'
end
