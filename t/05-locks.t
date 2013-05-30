#!perl
$ENV{PATH} = "/bin:/usr/bin";

use strict;
use Test::More;
use Test::Deep;
use Nagios::Agent;
use Time::HiRes;
use Cwd;
use POSIX ":sys_wait_h";
do "t/common.pl";

{
	is_deeply(Nagios::Agent::keymaster(), {}, "%LOCKS starts off life empty");
	ok(Nagios::Agent::lock("mylock"), "basic locking works");
	ok(Nagios::Agent::locked('mylock'), "locked indicates 'mylock' is locked");
	my $previous_lock = Nagios::Agent::keymaster()->{mylock};
	ok(! Nagios::Agent::lock("mylock"), "Locking something already locked fails");
	is_deeply(Nagios::Agent::keymaster()->{mylock}, $previous_lock, "'mylock' lock doesn't change after calling a second time");
	ok(Nagios::Agent::unlock('mylock'), "Unlocking can unlock the lock");
	my $locks = Nagios::Agent::keymaster;
	cmp_deeply($locks,
		{
			mylock => {
				locked      => 0,
				locked_at   => re('^\d+(\.\d+)?$'),
				unlocked_at => re('^\d+(\.\d+)?$'),
			},
		},
		"keymaster returns expected hash");
	ok($locks->{unlocked_at} >= $locks->{locked_at}, "unlocked_at > locked_at for unlocked lock");
	ok(! Nagios::Agent::locked('mylock'), "locked indicates 'mylock' is unlocked");
}

{
	my $lock_time = time;
	my $locked_at = 5;
	ok(Nagios::Agent::lock("mycustomlock", locked => 0, locked_by => "me", locked_at => $locked_at), "Lock with parameters works");
	my $expect = {
			locked => 1,
			locked_by => 'me',
			locked_at => re('^\d+(\.\d+)?$'),
	};

	my $locks = Nagios::Agent::keymaster;
	cmp_deeply($locks->{'mycustomlock'}, $expect, "mycustomlock is filled out as expected");
	my $offset = $locks->{'mycustomlock'}{locked_at} - $lock_time;
	ok($offset >= 0 && $offset <= 1, "'locked_at' is within 1 sec of when we calculated: $offset");
	ok($locks->{'mycustomlock'}{locked_at} != $locked_at, "lock time was not overridden to epoch time '$locked_at'");
}


done_testing;
