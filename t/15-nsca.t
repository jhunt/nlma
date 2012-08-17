#!perl

$ENV{PATH} = "/bin:/usr/bin";

use Test::More;
use Nagios::Agent;

my $SEND_NSCA = "t/bin/send_nsca";

{

	my $FILE = "t/tmp/1.2.3.4.5667.nsca";
	unlink $FILE if -f $FILE;

	Nagios::Agent::send_nsca("1.2.3.4:5667", $SEND_NSCA, "mock_host",
		{
			name => 'check1',
			exit_status => 0,
			output => "OK:check1 is fine"
		},
		{
			name => 'check2',
			exit_status => 2,
			output => "CRIT:check2 is critical"
		}
	);

	ok(-f $FILE, "mock_send_nsca wrote to $FILE");
	open my $fh, "<", $FILE or fail("couldn't open $FILE: $!");
	my $line;

	# \x17 is required for nsca to properly process results...
	local $/ = "\n\x17";

	$line = <$fh>;
	is($line, "mock_host\tcheck1\t0\tOK:check1 is fine\n\x17", "line 1 is correct");

	$line = <$fh>;
	is($line, "mock_host\tcheck2\t2\tCRIT:check2 is critical\n\x17", "line 2 is correct");

	close $fh;
}

done_testing;
