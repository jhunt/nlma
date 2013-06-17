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
	is_deeply(Nagios::Agent::keymaster, {}, "%LOCKS starts off life empty");
	ok(Nagios::Agent::lock("mylock"), "basic locking works");
	ok(Nagios::Agent::locked('mylock'), "locked indicates 'mylock' is locked");

	my $previous_lock = Nagios::Agent::keymaster->{mylock};
	cmp_deeply($previous_lock, {
			locked      => 1,
			locked_at   => re(qr/^\d+(\.\d+)?$/),
			unlocked_at => -1, # never unlocked
		}, "lock created without attributes is bare");

	ok(! Nagios::Agent::lock("mylock"), "Locking something already locked fails");
	is_deeply(Nagios::Agent::keymaster->{mylock}, $previous_lock, "'mylock' lock doesn't change after calling a second time");
	ok(Nagios::Agent::unlock('mylock'), "Unlocking can unlock the lock");

	my $locks = Nagios::Agent::keymaster;
	cmp_deeply($locks,
		{
			mylock => {
				locked      => 0,
				locked_at   => re(qr/^\d+(\.\d+)?$/),
				unlocked_at => re(qr/^\d+(\.\d+)?$/),
			},
		},
		"keymaster returns expected hash");
	ok($locks->{mylock}{unlocked_at} >= $locks->{mylock}{locked_at}, "unlocked_at > locked_at for unlocked lock");
	ok(! Nagios::Agent::locked('mylock'), "locked indicates 'mylock' is unlocked");
}

{
	ok(Nagios::Agent::lock("mycustomlock",
			locked      => 0,
			locked_by   => "me",
			locked_at   => 5,
			unlocked_at => 6,
		), "Lock with parameters works");

	cmp_deeply(Nagios::Agent::keymaster->{'mycustomlock'}, {
			locked      => 1,
			locked_by   => "me", # honored
			locked_at   => code(sub { shift != 5 }),
			unlocked_at => -1,
		} , "mycustomlock is filled out as expected");
}

{ # unlocked_at should persist through a lock() call
	ok(!Nagios::Agent::locked('gatekeeper'), "[test sanity] gatekeeper is not locked");

	# Lock it once
	ok(Nagios::Agent::lock('gatekeeper'), "locked 1st time");
	is(Nagios::Agent::keymaster->{gatekeeper}{unlocked_at}, -1, "unlocked_at is initially -1");

	# Unlock it
	ok(Nagios::Agent::unlock('gatekeeper'), "unlocked 1st time");
	isnt(Nagios::Agent::keymaster->{gatekeeper}{unlocked_at}, -1, "unlocked_at is set to a real timestamp");

	# Lock it again
	ok(Nagios::Agent::lock('gatekeeper'), "locked 2nd time");
	isnt(Nagios::Agent::keymaster->{gatekeeper}{unlocked_at}, -1, "unlocked_at is still set");
}


done_testing;
