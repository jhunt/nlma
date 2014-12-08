#!perl

use Test::More;
do "t/common.pl";
use NLMA;
use File::Temp qw(tempfile);

plan skip_all => "Set TEST_ALL to enable drop_privs tests" unless TEST_ALL();
plan skip_all => "Run the test suite as root to enable drop_privs tests"
	unless $) == 0 and $( == 0;

{
	my ($fh, $tempfile) = tempfile();

	my ($user, $group) = qw(nlma nlma);
	my ($uid, $gid) = (411, 411);

	# This is tricky... we need to chown the files in cover_db
	# to be owned by the user/group we are going to drop privs to

	qx(chown -R $user:$group cover_db) if -d 'cover_db';

	my $pid = fork;
	if ($pid == 0) {
		NLMA::drop_privs("nlma", "nlma");
		print $fh "EUID:$>\n";
		print $fh "RUID:$<\n";
		print $fh "EGID:$)\n";
		print $fh "RGID:$(\n";
		close $fh;
		exit 0;
	}
	close $fh;

	waitpid($pid, 0);
	open $fh, '<', $tempfile or BAIL_OUT("Failed to open $tempfile to read drop_privs results: $!");
	my $line;

	$line = <$fh>; chomp $line;
	is($line, "EUID:411", "drop_privs EUID");
	$line = <$fh>; chomp $line;
	is($line, "RUID:411", "drop_privs RUID");
	$line = <$fh>; $line =~ s/\s.*//; chomp $line;
	is($line, "EGID:411", "drop_privs EGID");
	$line = <$fh>; $line =~ s/\s.*//; chomp $line;
	is($line, "RGID:411", "drop_privs RGID");
	close $fh;
}

done_testing;
