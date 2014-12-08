#!perl

use Test::More;
use NLMA;

{ # Schedule check, normal
	my $check = {
		name           => "test",
		interval       => 100,
		retry          => 10,
		is_soft_state  => 0,
		started_at     => 3000,
	};

	NLMA::schedule_check($check);
	is_deeply($check, {
			name           => "test",
			interval       => 100,
			retry          => 10,
			is_soft_state  => 0,
			started_at     => 3000,
			next_run       => 3100,
		}, "Re-scheduled 100s from last run");

	$check->{started_at} = 3105;
	$check->{is_soft_state} = 1;

	NLMA::schedule_check($check);
	is_deeply($check, {
			name           => "test",
			interval       => 100,
			retry          => 10,
			is_soft_state  => 1,
			started_at     => 3105,
			next_run       => 3115,
		}, "Re-schedule soft state is <retry> seconds from last started_at");

	my $NOW = time;
	$check->{started_at} = $check->{next_run} = 0;
	$check->{is_soft_state} = 0;
	NLMA::schedule_check($check);
	cmp_ok($check->{next_run}, '>=', $NOW - 5 + 100, "next_run scheduled relative to now");
}

done_testing;
