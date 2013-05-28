#!perl
$ENV{PATH} = "/bin:/usr/bin";

use strict;
use Test::More;
use Nagios::Agent;
use Cwd;
use POSIX ":sys_wait_h";
do "t/common.pl";

#use Log::Log4perl qw(:easy);
#Log::Log4perl->easy_init($DEBUG);

{
	is_deeply(Nagios::Agent::keymaster(), {}, "%LOCKS starts off life empty");
	ok(Nagios::Agent::lock("mylock"), "basic locking works");
	ok(Nagios::Agent::keymaster()->{mylock}->{locked}, "mylock is actually locked");
	ok(Nagios::Agent::keymaster()->{mylock}{locked_at} =~ /^\d+$/, "locked_at is digits");
	ok(Nagios::Agent::locked('mylock'), "locked indicates 'mylock' is locked");
	my $previous_lock = Nagios::Agent::keymaster()->{mylock};
	ok(! Nagios::Agent::lock("mylock"), "Locking something already locked fails");
	is_deeply(Nagios::Agent::keymaster()->{mylock}, $previous_lock, "'mylock' lock doesn't change after calling a second time");
	ok(Nagios::Agent::unlock('mylock'), "Unlocking can unlock the lock");
	is_deeply(Nagios::Agent::keymaster(), {}, "%LOCKS is empty again");
	ok(! Nagios::Agent::locked('mylock'), "locked indicates 'mylock' is unlocked");
}

{
	my $lock_time = time;
	ok(Nagios::Agent::lock("mycustomlock", locked_by => "me", locked_at => $lock_time), "Lock with parameters works");
	my $expect = {
		mycustomlock => {
			locked => 1,
			locked_by => 'me',
			locked_at => $lock_time,
		}
	};

	is_deeply(Nagios::Agent::keymaster, $expect, "mycustomlock is filled out as expected");
}


done_testing;
