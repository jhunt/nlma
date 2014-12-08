#!perl

use Test::More;
use Test::Deep;
use NLMA;

{
	my ($config, $checks) = NLMA::parse_config('t/data/config/grouped.yml');
	my $filtered;

	$checks = [sort { $a->{name} cmp $b->{name} } @$checks];
	cmp_deeply([
			$checks->[0]{group},
			$checks->[1]{group},
			$checks->[2]{group},
			$checks->[3]{group}, # check4 - default of 'default'
		], [qw/feeders feeders filers default/],
		"Check Groups parsed");

	$filtered = NLMA::filter_checks($checks, "feeders,filers");
	cmp_deeply(
		[map { $_->{name} } @$filtered],
		[qw/check1 check2 check3/],
		"Filtered to just feeders and filers");

	$filtered = NLMA::filter_checks($checks, "feeders, filers");
	cmp_deeply(
		[map { $_->{name} } @$filtered],
		[qw/check1 check2 check3/],
		"Filtered to just feeders and filers (extra whitespace)");

	$filtered = NLMA::filter_checks($checks, "filers");
	cmp_deeply(
		[map { $_->{name} } @$filtered],
		[qw/check3/],
		"Filtered to just filers");

	$filtered = NLMA::filter_checks($checks, undef);
	cmp_deeply(
		[map { $_->{name} } @$filtered],
		[qw/check4/],
		"Filtered to ungrouped checks");

	$filtered = NLMA::filter_checks($checks, "all");
	cmp_deeply(
		[map { $_->{name} } @$filtered],
		[qw/check1 check2 check3 check4/],
		"Filtered to all checks");

	$filtered = NLMA::filter_checks($checks, "all,feeders");
	cmp_deeply(
		[map { $_->{name} } @$filtered],
		[qw/check1 check2 check3 check4/],
		"Filtered to all (extra 'feeders' group) checks");

	$filtered = NLMA::filter_checks($checks, "bogus");
	cmp_deeply(
		[map { $_->{name} } @$filtered],
		[],
		"Filtered to bogus group of checks (empty!)");
}

{ # global group configs
	my ($config, $checks) = NLMA::parse_config('t/data/config/grouped.yml');
	cmp_deeply({
			name         => 'default',
			min_interval => 300,
			splay        => 10000,
			count        => 1,
		},
		$config->{groups}{default},
		"Default group inherits splay from global");

	cmp_deeply({
			name         => 'filers',
			min_interval => 300,
			splay        => 10000,
			count        => 1,
		}, $config->{groups}{filers},
		"Detected filers group from check definitions");

	cmp_deeply({
			name         => 'feeders',
			min_interval => 300,
			splay        => 120,
			count        => 2,
		}, $config->{groups}{feeders},
		"feeders group is explicitly configured");
}

{ # per-group splay
	my ($config, $checks) = NLMA::parse_config('t/data/config/grouped.yml');
	$checks = [sort { $a->{name} cmp $b->{name} } @$checks];

	is(abs($checks->[0]{next_run} - $checks->[1]{next_run}), 120,
		"splay between feeders checks is 120");
	is($checks->[0]{next_run}, $checks->[2]{next_run},
		"all groups start at the same point in time");
}

done_testing;
