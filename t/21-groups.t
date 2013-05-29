#!perl

use Test::More;
use Test::Deep;
use Nagios::Agent;

{
	my ($config, $checks) = Nagios::Agent::parse_config('t/data/config/grouped.yml');
	my $filtered;

	$checks = [sort { $a->{name} cmp $b->{name} } @$checks];
	cmp_deeply([
			$checks->[0]{group},
			$checks->[1]{group},
			$checks->[2]{group},
			$checks->[3]{group}, # check4 - default of 'default'
		], [qw/feeders feeders filers default/],
		"Check Groups parsed");

	$filtered = Nagios::Agent::filter_checks($checks, "feeders,filers");
	cmp_deeply(
		[map { $_->{name} } @$filtered],
		[qw/check1 check2 check3/],
		"Filtered to just feeders and filers");

	$filtered = Nagios::Agent::filter_checks($checks, "feeders, filers");
	cmp_deeply(
		[map { $_->{name} } @$filtered],
		[qw/check1 check2 check3/],
		"Filtered to just feeders and filers (extra whitespace)");

	$filtered = Nagios::Agent::filter_checks($checks, "filers");
	cmp_deeply(
		[map { $_->{name} } @$filtered],
		[qw/check3/],
		"Filtered to just filers");

	$filtered = Nagios::Agent::filter_checks($checks, undef);
	cmp_deeply(
		[map { $_->{name} } @$filtered],
		[qw/check4/],
		"Filtered to ungrouped checks");

	$filtered = Nagios::Agent::filter_checks($checks, "all");
	cmp_deeply(
		[map { $_->{name} } @$filtered],
		[qw/check1 check2 check3 check4/],
		"Filtered to all checks");

	$filtered = Nagios::Agent::filter_checks($checks, "all,feeders");
	cmp_deeply(
		[map { $_->{name} } @$filtered],
		[qw/check1 check2 check3 check4/],
		"Filtered to all (extra 'feeders' group) checks");

	$filtered = Nagios::Agent::filter_checks($checks, "bogus");
	cmp_deeply(
		[map { $_->{name} } @$filtered],
		[],
		"Filtered to bogus group of checks (empty!)");
}

done_testing;
