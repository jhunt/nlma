#!perl
$ENV{PATH} = "/bin:/usr/bin";

use strict;
use Test::More;
use Nagios::Agent;
use Cwd;
use POSIX ":sys_wait_h";
use Test::MockModule;
do "t/common.pl";

plan skip_all => "Set TEST_ALL to enable run_check tests" unless TEST_ALL();

use Log::Log4perl qw(:easy);
#Log::Log4perl->easy_init($DEBUG);

{ # run a check and test its output
	my ($config, $checks) = Nagios::Agent::parse_config("t/data/config/run1.yml");

	ok(Nagios::Agent::run_check($checks->[0], getcwd."/t/checks"), "run_check returns true");
	ok($checks->[0]{pipe}, "run_check sets up child->parent pipe");
	isnt($checks->[0]{pid}, -1, "run_check sets PID properly");

	my $rc;
	diag "Waiting on child PID ".$checks->[0]{pid};
	waitpid($checks->[0]{pid}, 0); $rc = $?;
	is($rc, 0x0000, "check exited 0");
	is(Nagios::Agent::reap_check($checks->[0], $rc), 0, "reap_check returns 0 on success");

	is($checks->[0]{pid}, -1, "reap_check unsets PID");
	is($checks->[0]{output}, "I am ".$ENV{USER}, "Output of check captured properly");
	is($checks->[0]{stderr}, "this is standard error\n", "STDERR of check captured");
}

{ # Check that we don't delete things from the check object when we run (ITM-3597)
	my ($config, $checks) = Nagios::Agent::parse_config("t/data/config/itm-3597.yml");

	is $checks->[0]{sudo}, "root", "check command set to run as root";
	Nagios::Agent::run_check($checks->[0], getcwd."/t/checks");
	is $checks->[0]{sudo}, "root", "check command is still set to run as root";
}

{ # Test locking
	my ($config, $checks) = Nagios::Agent::parse_config("t/data/config/locks.yml");
	ok(! Nagios::Agent::locked('locked_check'), "'locked_check' is not locked prior to running 'check_locks'");
	ok(Nagios::Agent::run_check($checks->[0], getcwd."/t/checks"), "run_check returns true");
	ok(Nagios::Agent::locked('locked_check'), "'locked_check' is locked by 'check_locks' check");

	waitpid($checks->[0]{pid}, 0); my $rc = $?;
	is(Nagios::Agent::reap_check($checks->[0], $rc), 0, "reap_check succeeded");
	ok(! Nagios::Agent::locked('locked_check'), "'locked_check' is unlocked after 'check_locks' was reaped");
}

{ # test rescheduling of locked checks
	my ($config, $checks) = Nagios::Agent::parse_config("t/data/config/locks.yml");
	my $next_run = $checks->[0]{next_run};
	is($checks->[0]{pid}, -1, "locked check does not have a pid prior to run_check");
	Nagios::Agent::lock('locked_check', locked_by => 'FAKE_LOCK');
	ok(Nagios::Agent::run_check($checks->[0], getcwd . "/t/checks"), "run_check returns true even when check is locked");
	my $offset = $checks->[0]{next_run} - ($next_run + 5);
	ok(($offset < 1 && $offset > 0), "locked check should be rescheduled out 5 seconds. interval was: $offset");
	is($checks->[0]{pid}, -1, "locked check does not have a pid after run_check");
	Nagios::Agent::unlock('locked_check');
}

{ # verify a failed check releases the lock
	my $module = Test::MockModule->new('Nagios::Agent');
	$module->mock('drop_privs', sub { return 0 });
	ok(! Nagios::Agent::locked('failed_check'), "LOCK{failed_check} is not set prior to running failed check");
	ok(! Nagios::Agent::runall("Nagios::Agent", "t/data/config/failed_check.yml"), "runall returns false on failed check");
	ok(! Nagios::Agent::locked('failed_check'), "LOCK{failed_check} is not set after running a failed check");
}

{ # Check that we Display STDERR Debug out (ITM-3987)
	my ($config, $checks) = Nagios::Agent::parse_config("t/data/config/itm-3987.yml");
	my $rc;

	Nagios::Agent::run_check($checks->[0], getcwd."/t/checks", 0);
	diag "Waiting on child PID ".$checks->[0]{pid};
	waitpid($checks->[0]{pid}, 0); $rc = $?;
	is($rc, 0x0000, "check exited 0");
	is(Nagios::Agent::reap_check($checks->[0], $rc), 0, "reap_check returns 0 on success");
	is($checks->[0]{output}, "DEBUG OK - Everything is debug", "STDOUT is correct for no debug");
	is($checks->[0]{stderr}, "", "NO STDERR of check for non-debug");

	Nagios::Agent::run_check($checks->[0], getcwd."/t/checks", 1);
	diag "Waiting on child PID ".$checks->[0]{pid};
	waitpid($checks->[0]{pid}, 0); $rc = $?;
	is($rc, 0x0000, "check exited 0");
	is(Nagios::Agent::reap_check($checks->[0], $rc), 0, "reap_check returns 0 on success");
	is($checks->[0]{output}, "DEBUG OK - Everything is debug", "STDOUT is correct for debug");
	is($checks->[0]{stderr}, "DEBUG> debug output\n", "STDERR of check captured for debug");

	Nagios::Agent::run_check($checks->[0], getcwd."/t/checks", 3);
	diag "Waiting on child PID ".$checks->[0]{pid};
	waitpid($checks->[0]{pid}, 0); $rc = $?;
	is($rc, 0x0000, "check exited 0");
	is(Nagios::Agent::reap_check($checks->[0], $rc), 0, "reap_check returns 0 on success");
	is($checks->[0]{output}, "DEBUG OK - Everything is debug", "STDOUT is correct for trace");
	is($checks->[0]{stderr}, "DEBUG> debug output\nTRACE> trace output\n", "STDERR of check captured for trace");
}

ok(1);

done_testing;
