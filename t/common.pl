sub TEST_ALL
{
	if (!exists $ENV{TEST_ALL}) {
		chomp(my $hostname = qx(hostname -f));
		$ENV{TEST_ALL} = ($hostname =~ m/\.opal\./ && $hostname !~ m/build/) ? 1 : 0;
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
	$check->{output} = ''           unless exists $check->{output};
	$check->{command} = 'check_it'  unless exists $check->{command};
	$check->{on_timeout} = 'UNKNOWN' unless exists $check->{on_timeout};

	$check;
}

# Create a fake, readable pipe.
#
# We used to use IO::String, but apparently IO::String handles don't
# emulate real UNIX file descriptors enough for IO::Select or select(3)'s
# tastes.
#
# BE CAREFUL not to put too much data into mock_pipe since it doesn't
# actually handle the deadlock well. (testing for that must be done via
# other mechanisms)
#
sub mock_pipe
{
	my ($s) = @_;

	pipe my $read, my $write;

	print $write $s;
	close $write;

	return $read;
}

1;
