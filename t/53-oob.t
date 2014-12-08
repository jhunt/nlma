#!perl

use Test::More;
use Test::Deep;
use Test::MockModule;
use NLMA;

{ # OOB alert processing
	my $check;
	my $CONFIG = "t/data/config/oob.yml";

	my $mocker = Test::MockModule->new("NLMA");
	# snag send_nsca()'s arg3
	$mocker->mock(send_nsca => sub { $check = $_[2]; });

	NLMA->submit_oob($CONFIG, {
		service  => "test_service",
		code     => 0,
		output   => "looks good"
	});
	cmp_deeply($check, {
		hostname    => "default-host",     # auto-host
		name        => "oob_test_service", # auto-prefix
		exit_status => 0,
		output      => "looks good (submitted via default-host)"
	}, "Check attributes for localhost");

	NLMA->submit_oob($CONFIG, {
		service  => "oob_thing",
		code     => 0,
		output   => "fine fine fine",
	});
	is($check->{name}, "oob_thing", "Prefixing de-duplication");

	NLMA->submit_oob($CONFIG, {
		service  => "other-guy",
		code     => 1,
		output   => "WARNING",
		host     => "some.other.host",
	});
	cmp_deeply($check, {
		hostname    => "some.other.host",
		name        => "oob_other-guy",
		exit_status => 1,
		output      => "WARNING (submitted via default-host)",
	}, "On-behalf-of OOB submission");
}

done_testing;
