sub TEST_ALL
{
	if (!exists $ENV{TEST_ALL}) {
		chomp(my $hostname = qx(hostname -f));
		$ENV{TEST_ALL} = ($hostname =~ m/\.opal\./) ? 1 : 0;
	}
	$ENV{TEST_ALL};
}

sub mock_exit
{
	my ($rc) = @_;
	qx(/bin/sh -c 'exit $rc');
	return $?;
}

sub mock_check
{
	my $check = shift;
	$check->{interval} = 300        unless exists $check->{interval};
	$check->{retry} = 60            unless exists $check->{retry};
	$check->{started_at} = time - 5 unless exists $check->{started_at};
	$check->{state} = 0             unless exists $check->{state};
	$check->{last_state} = 0        unless exists $check->{last_state};
	$check->{is_soft_state} = 0     unless exists $check->{is_soft_state};
	$check->{attempts} = 1          unless exists $check->{attempts};
	$check->{current} = 0           unless exists $check->{current};
	$check->{pid} = 4242            unless exists $check->{pid};

	$check;
}
