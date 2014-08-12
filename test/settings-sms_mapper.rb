# TODO: move these into a database or similar: whole point is these are flexible

# OTHER_AND_USERNUM_TO_FWD: which fwding number is used for each other/user pair
# USERNUM_TO_DEVICES: which devices should receive call/SMS for each user number
# DEFAULT_FWD: messages are sent to this number when no other/user pair matches
#
# SMS Mapper uses these to make FWD_AND_USERNUM_TO_OTHER and DEVICE_TO_USERNUMS.
# Note that a single device could map to multiple user numbers.  See SMS Mapper
# for details on how the contents of the below maps are validated.

OTHER_AND_USERNUM_TO_FWD = {
	['16463741212', '18082061212'] => '16026381212',
	['12122031212', '18082061212'] => '13035621212'
}

USERNUM_TO_DEVICES = {
	'18082061212' => ['12045151212', '19176361212']
}

DEFAULT_FWD = '16045711212'
