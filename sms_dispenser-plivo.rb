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

require_relative 'sms_dispenser.rb'
require_relative 'logger.rb'

require 'net/http'
require 'uri'

load 'settings-sms_dispenser-plivo.rb'	# contains the publishing credentials

puts 'auth id:'
puts AUTH_ID

def send_message(src, dst, msg)
	Logger.log 'about to send "' + msg + '" with source ' + src +
		' and destination ' + dst
	uri = URI.parse('https://api.plivo.com')
	http = Net::HTTP.new(uri.host, uri.port)
	http.use_ssl = true
	request = Net::HTTP::Post.new('/v1/Account/' + AUTH_ID + '/Message/')
	request.basic_auth AUTH_ID, AUTH_TOKEN
	request.add_field('Content-Type', 'application/json')
	request.body = JSON.dump({
		'src'	=> src,
		'dst'	=> dst,
		'text'	=> msg
	})
	response = http.request(request)
	# TODO: do something if the API response is bad (or do in SMSDispenser)
	return_code = 'API response: ' + response.to_s + 'with body "' +
		response.body + '"'
	Logger.log 'Plivo send attempt received ' + return_code
	return return_code
end

dispenser = SMSDispenser.new

Logger.log 'starting Sopranica Plivo SMS Dispenser v0.03'

trap(:INT) {
	Logger.log 'Plivo dispenser terminating at user request'
	# TODO: add lock? so don't close socket while in middle of processing
	dispenser.zmq_terminate
	exit
}
# TODO: add TERM handler?

dispenser.dispense_messages(method(:send_message))
