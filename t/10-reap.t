#!perl

use Test::More;
use Nagios::Agent;
use IO::String;
use File::Temp qw/tempfile/;
do "t/common.pl";

#  Tests in this suite only work because the reap_check function
#  doesn't really interact with a UNIX process; waitall does that.
#  Instead, it accepts a process exit status and a pipe to read
#  from.

my $NOW = time;

{ # Normal OK result

	my $check = mock_check({
			name => "check_ok",
			pipe => mock_pipe("all good"),
	});

	is(Nagios::Agent::reap_check($check, 0x0000), 0, "reap_check returns 0 on success");
	cmp_ok($check->{ended_at}, '>', $check->{started_at}, "check ended after it started");
	cmp_ok($check->{duration}, '>', 0, 'check duration was > 0');
	is($check->{is_soft_state}, 0, 'OK -> OK is not a soft state');
	is($check->{current}, 1, 'still on 1/1 attempts');
	is($check->{pid}, -1, 'check PID reset to -1');
	is($check->{output}, 'all good', 'read check output from pipe');
	ok(!$check->{pipe}, 'pipe closed and undefined');
	is($check->{state}, 0, "check state is now 0");
}

{ # ITM-1957 - Attempt #3172/1 bug
	my $check = mock_check({
			name          => "check_attempts",
			state         => 2, # Start out CRIT
			is_soft_state => 1,
			current       => 4321,
			attempts      => 3,
			pipe          => mock_pipe("still critical..."),
	});
	is(Nagios::Agent::reap_check($check, mock_exit(2)), 0, "reap_check returns 0 on success");
	is($check->{is_soft_state}, 0, 'After 4321/3 attempts, we are not at a soft state anymore');
	is($check->{current},  1, 'back to 1/3 attempts');
	is($check->{state},    2, 'Critical State');
}

{ # Weird return values (>3)
	my $check = mock_check({
			name => 'bad_rc',
			pipe => mock_pipe("returned 0x34")
	});

	is(Nagios::Agent::reap_check($check, 0x3400), 0, "reap_check returns 0 on success");
	is($check->{state}, 3, "check state is now 3");
}

{ # Weird return values (KILLED or TERMED)
	my $check = mock_check({
			name => 'bad_rc',
			sigkill => 1,
			pipe => mock_pipe("non-local exit")
	});

	is(Nagios::Agent::reap_check($check, 0x3401), 0, "reap_check returns 0 on success");
	is($check->{state}, 3, "check state is now 3");
	is($check->{output}, "check timed out (exceeded NLMA timeout)", 'KILLED should return timed-out output');
}

{ # ITM-2166 - STDERR output in place of STDOUT
	my ($fh, $temp) = tempfile;
	print $fh "this is a fail message\n";
	close $fh;

	my $check = mock_check({
			name       => 'bad_sudo',
			stderr_out => $temp,
			pipe       => mock_pipe(''), # no output
	});

	is(Nagios::Agent::reap_check($check, mock_exit(42)), 0, "reap_check returns 0 on success");
	is($check->{state}, 3, "check state is UNKNOWN if all we have is STDERR");
	is($check->{output}, "ERROR: this is a fail message");
}

{ # ITM-2166 - Force UNKNOWNs for missing STDOUT, regardless of exit code
	my ($fh, $temp) = tempfile;
	print $fh "errors are standard\n";
	close $fh;

	my $check = mock_check({
			name        => 'no_output',
			stderr_out  => $temp,
			pipe        => mock_pipe(''), # no output
	});

	is(Nagios::Agent::reap_check($check, mock_exit(1)), 0, "reap_check returns 0 on success");
	is($check->{state}, 3, "check state promotes to UNKNOWN if there is no STDOUT");
	is($check->{output}, "ERROR: errors are standard");
}

{ # ITM-2166 - Force UNKNOWNs for missing STDOUT, regardless of STDERR output
	my $check = mock_check({
			name => 'really_no_output',
			pipe => mock_pipe(''), # no output
	});

	is(Nagios::Agent::reap_check($check, mock_exit(1)), 0, "reap_check returns 0 on success");
	is($check->{state}, 3, "check state promotes to UNKNOWN if there is no STDOUT");
	is($check->{output}, "(no check output)");
}

{ # No check output
	my $check = mock_check({
			name => 'no_output',
			pipe => mock_pipe('')
	});
	is(Nagios::Agent::reap_check($check, 0x0000), 0, "reap_check returns 0 on success");
	is($check->{output}, "(no check output)", "no output message");
}

{ # failed to read from pipe
  # (still returns 0, since we incrementally read for ITM-2204)
	my $check = mock_check({
			name => 'bad_read',
			pipe => 'not-a-file-descriptor!'
	});
	diag "You should see a 'read() on unopened filehandle' warning below...";
	is(Nagios::Agent::reap_check($check, 0x0000), 0, "reap_check now returns 0 on read fail");
	is($check->{output}, "(no check output)", "no output message");
}

{ # Sustained Warning
	my $check = mock_check({
			name => 'warn_check',
			last_state => 1,
			state => 1,
			pipe => mock_pipe('still warning')
	});
	is(Nagios::Agent::reap_check($check, 0x0100), 0, "reap_check returns 0 on success");
	is($check->{is_soft_state}, 0, "WARNING -> WARNING is a hard state");
}

{ # Multiline output
	my $check = mock_check({
			name => 'multiline',
			pipe => mock_pipe(join("\n", qw(this is output on multiple lines))),
	});
	is(Nagios::Agent::reap_check($check, 0x0000), 0, "reap_check returns 0 on success");
	is($check->{output}, "this / is / output / on / multiple / lines");
}

done_testing;
