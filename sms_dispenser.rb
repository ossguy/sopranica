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

require_relative 'logger.rb'

require 'ffi-rzmq'
require 'json'

class SMSDispenser
	def zmq_terminate
		# TODO: add lock? so don't close sock while in middle of recving
		Logger.log 'dispenser terminating at user request'
		@monitor.close
		@receiver.close
		@zmq_context.terminate
	end

	def dispense_messages(send_message_method)
		Logger.log 'starting Sopranica SMS Dispenser v0.04'

		@zmq_context = ZMQ::Context.new

		@monitor = @zmq_context.socket(ZMQ::PULL)
		@monitor.connect('ipc://spr-dispenser000-monitor')

		@receiver = @zmq_context.socket(ZMQ::PULL)
		@receiver.connect('ipc://spr-dispenser000-receiver')

		poller = ZMQ::Poller.new
		poller.register(@monitor, ZMQ::POLLIN)
		poller.register(@receiver, ZMQ::POLLIN)

		loop do
			Logger.log 'starting poll...'
			poller.poll(60000)	# block 60 s, process or repeat

			poller.readables.each do |socket|
				# TODO: also check monitor when it's implemented

				@receiver.recv_string(stuff = '')
				Logger.log 'recved a msg (raw): ' + stuff
				zmq_msg = JSON.parse stuff
				Logger.log 'formatted message: ' + zmq_msg.to_s
				if zmq_msg['message_type'] != 'to_other' then
					Logger.log 'unknown msg type: ' \
						+ zmq_msg['message_type']
				else
					rv = send_message_method.call(
						zmq_msg['user_number'],
						zmq_msg['others_number'],
						zmq_msg['body'])

					Logger.log 'sent message "' \
						+ zmq_msg['body'] + '" from ' \
						+ zmq_msg['user_number'] \
						+ ' to ' \
						+ zmq_msg['others_number'] \
						+ '; return value: ' + rv
					# TODO: do something if API response bad
				end
			end
			Logger.log '...done poll stuff'
		end
	end
end
