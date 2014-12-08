#!perl

use Test::More;
use NLMA;

{
	is($NLMA::RECONFIG, 0, "RECONFIG is initially 0");
	NLMA::sighup_handler;
	is($NLMA::RECONFIG, 1, "RECONFIG is 1 after SIGHUP");

	is($NLMA::TERM, 0, "TERM is initially 0");
	NLMA::sigterm_handler;
	is($NLMA::TERM, 1, "TERM is 1 after SIGTERM");

	is($NLMA::DUMPCONFIG, 0, "DUMPCONFIG is initially 0");
	NLMA::sigusr1_handler;
	is($NLMA::DUMPCONFIG, 1, "DUMPCONFIG is 1 after SIGUSR1");
}

done_testing;
