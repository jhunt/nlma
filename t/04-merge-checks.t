#!perl

use Test::More;
use Nagios::Agent;

my $NOW = time;

{ # Merging of check defs is additive

	my $old = [
		{
			hostname    => 'localhost',
			name        => 'check1',
			timeout     => 45,
			pid         => -1, # force re-schedule
			interval    => 300,
			retry       => 60,
			attempts    => 1,
			command     => 'check_stuff',
			environment => 'default',

			started_at  => $NOW - 200,
			ended_at    => $NOW - 200 + 5,
			next_run    => $NOW + 100,
		},
		{
			hostname    => 'localhost',
			name        => 'check2',
			timeout     => 45,
			on_timeout  => "critical",
			pid         => 1010, # to avoid re-scheduling
			interval    => 300,
			retry       => 60,
			attempts    => 1,
			command     => 'check_stuff',
			environment => 'default',
			group       => 'G2',

			started_at  => $NOW,
			next_run    => $NOW
		},
		{
			name     => 'delete-me', # this check should get removed
		}
	];

	my $new = [ # can be in any order!
		{ # update check2 with a new timeout / group
			name        => 'check2',
			hostname    => $old->[1]{hostname},    # unchanged
			environment => $old->[1]{environment}, # unchanged
			command     => $old->[1]{command},     # unchanged
			interval    => $old->[1]{interval},    # unchanged
			timeout     => 10,
			on_timeout  => "warning",
			group       => 'group #2',
		},
		{ # update check1 with new intervals
			name        => 'check1',
			hostname    => $old->[0]{hostname},    # unchanged
			environment => 'staging',
			command     => $old->[0]{command},     # unchanged
			interval    => 60,
			attempts    => 4,
			retry       => 15,
			timeout     => $old->[0]{timeout},     # unchanged
		},
		{ # Create new check (check3)
			name        => 'check3',
			hostname    => 'localhost',
			timeout     => 40,
			pid         => -1,
			interval    => 30,
			retry       => 6,
			attempts    => 2,
			command     => 'check_stuff',
			environment => 'default',
		},
	];

	is(Nagios::Agent::merge_check_defs($old, $new), 0, "merge_check_defs returns 0");

#	$old->[0]{started_at} = $old->[0]{ended_at} = $old->[0]{next_run}   = 42;
	is_deeply($old->[0], {
			name        => "check1",
			hostname    => 'localhost',
			timeout     => 45,
			pid         => -1,
			interval    => 60, # CHANGED
			retry       => 15, # CHANGED
			attempts    =>  4, # CHANGED
			command     => 'check_stuff',
			environment => 'staging', # CHANGED

			# check is rescheduled
			started_at  => $NOW - 200,      # same
			ended_at    => $NOW - 200 + 5,  # same
			next_run    => $NOW - 200 + 60, # reschedule with new interval
		}, "check definitions merged for check1");

	is_deeply($old->[1], {
			name        => "check2",
			hostname    => 'localhost',
			timeout     => 10, # CHANGED
			on_timeout  => "warning", # CHANGED
			pid         => 1010,
			interval    => 300,
			retry       => 60,
			attempts    =>  1,
			command     => 'check_stuff',
			environment => 'default',
			group       => 'group #2', # CHANGED

			# check is rescheduled
			started_at  => $NOW, # same
			next_run    => $NOW, # same
		}, "check definitions merged for check2");

	is($old->[2]{deleted}, 1, "delete-me check got deleted");

	is_deeply($old->[3], {
			name        => "check3",
			hostname    => 'localhost',
			timeout     => 40,
			pid         => -1,
			interval    => 30,
			retry       => 6,
			attempts    => 2,
			command     => 'check_stuff',
			environment => 'default',
		}, "check definition created for new check3");
}

{ # merge checks for the same check name, different hosts (ITM-2417)

	my $old = [
		{
			hostname => 'hosta',
			name     => 'check1',
			timeout  => 45,
			pid      => -1,
			interval => 300,
			retry    => 60,
			attempts => 1,
			command  => 'check_stuff',
			environment => 'default',

			started_at => $NOW - 200,
			ended_at   => $NOW - 200 + 5,
			next_run   => $NOW + 100,
		},
		{
			hostname => 'hostb',
			name     => 'check1',
			timeout  => 45,
			pid      => -1,
			interval => 300,
			retry    => 60,
			attempts => 1,
			command  => 'check_stuff',
			environment => 'default',

			started_at => $NOW - 50,
			ended_at   => $NOW - 200 + 5,
			next_run   => $NOW - 200 + 300,
		}
	];

	is(Nagios::Agent::merge_check_defs($old, $old), 0, "merge_check_defs returns 0");

	is_deeply($old->[0], {
			name        => "check1",
			hostname    => 'hosta',
			timeout     => 45,
			pid         => -1,
			interval    => 300,
			retry       => 60,
			attempts    =>  1,
			command     => 'check_stuff',
			environment => 'default',

			# check is rescheduled
			started_at  => $NOW - 200,      # same
			ended_at    => $NOW - 200 + 5,  # same
			next_run    => $NOW - 200 + 300, # reschedule with existing interval
		}, "check definitions merged for hosta/check1");

	is_deeply($old->[1], {
			name        => "check1",
			hostname    => 'hostb',
			timeout     => 45,
			pid         => -1,
			interval    => 300,
			retry       => 60,
			attempts    =>  1,
			command     => 'check_stuff',
			environment => 'default',

			# check is rescheduled
			started_at  => $NOW - 50,      # same
			ended_at    => $NOW - 200 + 5,  # same
			next_run    => $NOW - 50 + 300, # reschedule with existing interval
		}, "check definitions merged for check2");

	is(@$old, 2, "Didn't lost any checks");
}

{ # merge sudo attribute intelligently
	my $old = {
			hostname => 'hosta',
			name     => 'check1',
			timeout  => 45,
			pid      => -1,
			interval => 300,
			retry    => 60,
			attempts => 1,
			command  => 'check_stuff',
			environment => 'default',
			# no sudo

			started_at => $NOW - 200,
			ended_at   => $NOW - 200 + 5,
			next_run   => $NOW + 100,
	};

	my $new = {
			hostname => 'hosta',
			name     => 'check1',
			timeout  => 45,
			pid      => -1,
			interval => 300,
			retry    => 60,
			attempts => 1,
			command  => 'check_stuff',
			environment => 'default',
			sudo     => 'root', # CHANGED
	};

	is(Nagios::Agent::merge_check_defs([$old], [$new]), 0, "merge_check_defs returns 0");
	is($old->{sudo}, "root", "sudo attribute set");

	$new->{sudo} = "xyzzy";
	is(Nagios::Agent::merge_check_defs([$old], [$new]), 0, "merge_check_defs returns 0");
	is($old->{sudo}, "xyzzy", "sudo attribute changed");

	delete $new->{sudo};
	is(Nagios::Agent::merge_check_defs([$old], [$new]), 0, "merge_check_defs returns 0");
	is($old->{sudo}, undef, "sudo attribute unset");
}

{ # locking should merge
	my $old = {
			hostname => 'hosta',
			name     => 'check1',
			timeout  => 45,
			pid      => -1,
			interval => 300,
			retry    => 60,
			attempts => 1,
			command  => 'check_stuff',
			environment => 'default',
			# no sudo

			started_at => $NOW - 200,
			ended_at   => $NOW - 200 + 5,
			next_run   => $NOW + 100,
	};

	my $new = {
			hostname => 'hosta',
			name     => 'check1',
			timeout  => 45,
			pid      => -1,
			interval => 300,
			retry    => 60,
			attempts => 1,
			command  => 'check_stuff',
			environment => 'default',
			lock     => 'test1',
	};

	is(Nagios::Agent::merge_check_defs([$old], [$new]), 0, "merge_check_defs returns 0");
	is($old->{lock}, "test1", "lock attribute set");

	$new->{lock} = "update1";
	is(Nagios::Agent::merge_check_defs([$old], [$new]), 0, "merge_check_defs returns 0");
	is($old->{lock}, "update1", "lock atttribute updated");

	delete $new->{lock};
	is(Nagios::Agent::merge_check_defs([$old], [$new]), 0, "merge_check_defs returns 0");
	is($old->{lock}, undef, "lock atttribute unset");
}

done_testing;
