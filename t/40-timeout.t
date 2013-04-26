#!perl

$ENV{PATH} = "/bin:/usr/bin";

use strict;
use Test::More;
use Cwd;
use Capture::Tiny ':all';
use POSIX qw/WIFEXITED WEXITSTATUS/;

require "t/common.pl";
my $CMD = "bin/nlma-timeout";
BAIL_OUT("Unable to find $CMD. Are you running from repo_root?") unless -f $CMD;

local $SIG{ALRM} = sub {
		BAIL_OUT("Sigalarm received during $0 testing."
			. " Something didn't time out properly inside it.");
	};
alarm 15;

{ # run timeout with a good check
	my $check = "check_ok";
	test_timeout($check,
		"CHECK OK - Everything is good\n",
		"",
		0,
	);
}

{ # run timeout with a crit check
	my $check = "check_crit";
	test_timeout($check,
		"CHECK CRITICAL - Everything is not so good\n",
		"",
		2,
	);
}

{ # run timeout with a timing out check
	my $check = "check_sigterm";
	test_timeout($check,
		"check timed out \\(exceeded NLMA timeout\\)\n",
		"check check_sigterm pid \\d+ exceeded soft_stop; sending SIGTERM\n",
		3,
	);
}

{ # run timeout with a check not responding to SIGTERM
	my $check = "check_sigkill";
	test_timeout($check,
		"check timed out \\(exceeded NLMA timeout\\)\n",
		"check check_sigkill pid \\d+ exceeded soft_stop; sending SIGTERM\ncheck check_sigkill pid \\d+ exceeded hard_stop; sending SIGKILL\n",
		3,
	);
}

sub test_timeout
{
	my ($check, $expect_stdout, $expect_stderr, $expect_code) = @_;

	my ($stdout, $stderr, @results) = capture(sub{system "$CMD -t 2 -n $check -- ".getcwd."/t/checks/$check";});
	my $rc = WIFEXITED($?) ? WEXITSTATUS($?) : -1;
	is($rc, $expect_code, "$check returns $expect_code");
	like($stdout, qr(^$expect_stdout$)m, "$check stdout matches expected");
	like($stderr, qr(^$expect_stderr$)m, "$check stderr matches expected");
}

done_testing;
