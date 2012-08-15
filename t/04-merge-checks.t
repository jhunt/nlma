#!perl

use Test::More;
use Nagios::Agent;

{ # Merging of check defs is additive
	my $NOW = time;

	my $old = [
		{
			name     => 'check1',
			timeout  => 45,
			pid      => -1, # force re-schedule
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
			name     => 'check2',
			timeout  => 45,
			pid      => 1010, # to avoid re-scheduling
			interval => 300,
			retry    => 60,
			attempts => 1,
			command  => 'check_stuff',
			environment => 'default',

			started_at => $NOW,
			next_run   => $NOW
		},
		{
			name     => 'delete-me', # this check should get removed
		}
	];

	my $new = [ # can be in any order!
		{ # update check2 with a new timeout
			name        => 'check2',
			environment => $old->[1]{environment}, # unchanged
			command     => $old->[1]{command},     # unchanged
			interval    => $old->[1]{interval},    # unchanged
			timeout     => 10,
		},
		{ # update check1 with new intervals
			name        => 'check1',
			environment => 'staging',
			command     => $old->[0]{command},     # unchanged
			interval    => 60,
			timeout     => $old->[0]{timeout},     # unchanged
		},
		{ # Create new check (check3)
			name     => 'check3',
			timeout  => 40,
			pid      => -1,
			interval => 30,
			retry    => 6,
			attempts => 2,
			command  => 'check_stuff',
			environment => 'default',
		},
	];

	is(Nagios::Agent::merge_check_defs($old, $new), 0, "merge_check_defs returns 0");

#	$old->[0]{started_at} = $old->[0]{ended_at} = $old->[0]{next_run}   = 42;
	is_deeply($old->[0], {
			name        => "check1",
			timeout     => 45,
			pid         => -1,
			interval    => 60, # CHANGED
			retry       => 60,
			attempts    =>  1,
			command     => 'check_stuff',
			environment => 'staging', # CHANGED

			# check is rescheduled
			started_at  => $NOW - 200,      # same
			ended_at    => $NOW - 200 + 5,  # same
			next_run    => $NOW - 200 + 60, # reschedule with new interval
		}, "check definitions merged for check1");

	is_deeply($old->[1], {
			name        => "check2",
			timeout     => 10, # CHANGED
			pid         => 1010,
			interval    => 300,
			retry       => 60,
			attempts    =>  1,
			command     => 'check_stuff',
			environment => 'default',

			# check is rescheduled
			started_at  => $NOW, # same
			next_run    => $NOW, # same
		}, "check definitions merged for check2");

	is($old->[2]{deleted}, 1, "delete-me check got deleted");

	is_deeply($old->[3], {
			name        => "check3",
			timeout     => 40,
			pid         => -1,
			interval    => 30,
			retry       => 6,
			attempts    => 2,
			command     => 'check_stuff',
			environment => 'default',
		}, "check definition created for new check3");
}

done_testing;
