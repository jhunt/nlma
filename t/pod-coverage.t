use strict;
use warnings;
use Test::More;

sub TEST_ALL
{
	if (!exists $ENV{TEST_ALL}) {
		chomp(my $hostname = qx(hostname -f));
		$ENV{TEST_ALL} = ($hostname =~ m/\.opal\./) ? 1 : 0;
	}
	$ENV{TEST_ALL};
}

plan skip_all => "Enable TEST_ALL to test POD coverage" unless TEST_ALL;

# Ensure a recent version of Test::Pod::Coverage
my $min_tpc = 1.08;
eval "use Test::Pod::Coverage $min_tpc";
plan skip_all => "Test::Pod::Coverage $min_tpc required for testing POD coverage"
    if $@;

# Test::Pod::Coverage doesn't require a minimum Pod::Coverage version,
# but older versions don't recognize some common documentation styles
my $min_pc = 0.18;
eval "use Pod::Coverage $min_pc";
plan skip_all => "Pod::Coverage $min_pc required for testing POD coverage"
    if $@;

all_pod_coverage_ok();
