#!perl
$ENV{PATH} = "/bin:/usr/bin";

use strict;
use Test::More;
use Test::Deep;
use NLMA;
use Time::HiRes;
use Cwd;
use POSIX ":sys_wait_h";
do "t/common.pl";

{
	is_deeply(NLMA::keymaster, {}, "%LOCKS starts off life empty");
	ok(NLMA::lock("mylock"), "basic locking works");
	ok(NLMA::locked('mylock'), "locked indicates 'mylock' is locked");

	my $previous_lock = NLMA::keymaster->{mylock};
	cmp_deeply($previous_lock, {
			locked      => 1,
			locked_at   => re(qr/^\d+(\.\d+)?$/),
			unlocked_at => -1, # never unlocked
		}, "lock created without attributes is bare");

	ok(! NLMA::lock("mylock"), "Locking something already locked fails");
	is_deeply(NLMA::keymaster->{mylock}, $previous_lock, "'mylock' lock doesn't change after calling a second time");
	ok(NLMA::unlock('mylock'), "Unlocking can unlock the lock");

	my $locks = NLMA::keymaster;
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
	ok(! NLMA::locked('mylock'), "locked indicates 'mylock' is unlocked");
}

{
	ok(NLMA::lock("mycustomlock",
			locked      => 0,
			locked_by   => "me",
			locked_at   => 5,
			unlocked_at => 6,
		), "Lock with parameters works");

	cmp_deeply(NLMA::keymaster->{'mycustomlock'}, {
			locked      => 1,
			locked_by   => "me", # honored
			locked_at   => code(sub { shift != 5 }),
			unlocked_at => -1,
		} , "mycustomlock is filled out as expected");
}

{ # unlocked_at should persist through a lock() call
	ok(!NLMA::locked('gatekeeper'), "[test sanity] gatekeeper is not locked");

	# Lock it once
	ok(NLMA::lock('gatekeeper'), "locked 1st time");
	is(NLMA::keymaster->{gatekeeper}{unlocked_at}, -1, "unlocked_at is initially -1");

	# Unlock it
	ok(NLMA::unlock('gatekeeper'), "unlocked 1st time");
	isnt(NLMA::keymaster->{gatekeeper}{unlocked_at}, -1, "unlocked_at is set to a real timestamp");

	# Lock it again
	ok(NLMA::lock('gatekeeper'), "locked 2nd time");
	isnt(NLMA::keymaster->{gatekeeper}{unlocked_at}, -1, "unlocked_at is still set");
}


done_testing;
