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

load 'settings-sms_relay.rb'	# has LOGIN_USER, LOGIN_PWD, and DESTINATION_JID

module SMSRelay
	extend Blather::DSL

	def self.log(msg)
		t = Time.now
		puts "LOG %d.%09d: %s" % [t.to_i, t.nsec, msg]
	end

	def self.log_raw(msg)
		puts msg
	end

	def self.run
		EM.run { client.run }
	end

	setup LOGIN_USER, LOGIN_PWD

	when_ready { log 'ready to send messages; TODO - block send until now' }

	message :chat?, :body do |m|
		log 'iMSG - ' + m.from.node + ' -> ' + m.to.node + ': ' + m.body
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

SMSRelay.log 'starting Sopranica SMS Relay v0.01'

trap(:INT) { EM.stop }
trap(:TERM) { EM.stop }

Thread.new { SMSRelay.run }

count = 0
tmp = gets
while tmp == "\n" do
	msg = Blather::Stanza::Message.new(DESTINATION_JID, 'TesT' + count.to_s)
	SMSRelay.log '>>> sending message ==>'
	SMSRelay.log_raw msg.inspect
	SMSRelay.log '<== end of message to send'

	SMSRelay.log 'oMSG - ' + SMSRelay.jid.node + ' -> ' + msg.to.node \
		+ ': ' + msg.body
	SMSRelay.write_to_stream msg
	SMSRelay.log 'oMSG [sent]'

	count += 1
	tmp = gets
end

SMSRelay.log 'application terminating at user request'
