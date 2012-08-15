#!perl
$ENV{PATH} = "/bin:/usr/bin";

use Test::More;
use Nagios::Agent;
use Cwd;
use POSIX ":sys_wait_h";
do "t/common.pl";

plan skip_all => "Set TEST_ALL to enable run_check tests" unless TEST_ALL();
plan skip_all => "Cannot run these tests until we fix STDERR handling";

use Log::Log4perl qw(:easy);
#Log::Log4perl->easy_init($DEBUG);

{ # sudo option
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
	is($checks->[0]{output}, "I am ".$ENV{USER}, "Output of as_me captured properly");
}

ok(1);

done_testing;
