#!perl
$ENV{PATH} = "/bin:/usr/bin";

use Test::More;
use Nagios::Agent;
use Cwd;
use POSIX ":sys_wait_h";
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

ok(1);

done_testing;
