#!perl

use Test::More;
use Nagios::Agent;

{ # dumb helper functions

	is(Nagios::Agent::MAX(1,2), 2, "MAX works on positive integers");
	is(Nagios::Agent::MAX(2,1), 2, "MAX works on positive integers");

	is(Nagios::Agent::MIN(1,2), 1, "MIN works on positive integers");
	is(Nagios::Agent::MIN(2,1), 1, "MIN works on positive integers");

	is(Nagios::Agent::MAX(-4,-10), -4, "MAX works on negative integers");
	is(Nagios::Agent::MAX(-10,-4), -4, "MAX works on negative integers");

	is(Nagios::Agent::MIN(-4,-10), -10, "MIN works on negative integers");
	is(Nagios::Agent::MIN(-10,-4), -10, "MIN works on negative integers");

	is(Nagios::Agent::MAX(-2, 2), 2, "MAX works on positive/negative integers");
	is(Nagios::Agent::MAX(2, -2), 2, "MAX works on positive/negative integers");

	is(Nagios::Agent::MIN(-2, 2), -2, "MIN works on positive/negative integers");
	is(Nagios::Agent::MIN(2, -2), -2, "MIN works on positive/negative integers");
}

done_testing;
