#!perl

use Test::More;
use Nagios::Agent;

{
	is($Nagios::Agent::RECONFIG, 0, "RECONFIG is initially 0");
	Nagios::Agent::sighup_handler;
	is($Nagios::Agent::RECONFIG, 1, "RECONFIG is 1 after SIGHUP");

	is($Nagios::Agent::TERM, 0, "TERM is initially 0");
	Nagios::Agent::sigterm_handler;
	is($Nagios::Agent::TERM, 1, "TERM is 1 after SIGTERM");

	is($Nagios::Agent::DUMPCONFIG, 0, "DUMPCONFIG is initially 0");
	Nagios::Agent::sigusr1_handler;
	is($Nagios::Agent::DUMPCONFIG, 1, "DUMPCONFIG is 1 after SIGUSR1");
}

done_testing;
