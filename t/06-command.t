#!perl

use Test::More;
use NLMA;

my $check = {
	command  => "/bin/echo TEST OK",
	timeout  => 45,
	hostname => 'localhost',
	name     => 'test',
	sudo     => undef,
	env      => undef,
};

is NLMA::render_cmd($check), "/bin/echo TEST OK", "command renders properly for basic checks";

is NLMA::render_cmd($check, undef, 1), "/bin/echo TEST OK -D",
	"command renders properly for basic checks with debugging";
is NLMA::render_cmd($check, undef, 3), "/bin/echo TEST OK -D -D -D",
	"command renders properly for basic checks with trace debugging";

$check->{sudo} = "testuser";
is NLMA::render_cmd($check),
	"/usr/bin/sudo -n -u testuser  /usr/bin/nlma-timeout -t 45 -n 'localhost/test' -- /bin/echo TEST OK",
	"command renders properly for checks with sudo";

$check->{env} = { TEST_RUNNING => "true" };
is NLMA::render_cmd($check),
	"/usr/bin/sudo -n -u testuser TEST_RUNNING=true /usr/bin/nlma-timeout -t 45 -n 'localhost/test' -- /bin/echo TEST OK",
	"command renders properly checks with sudo + environment variables";

$check->{sudo} = undef;
is NLMA::render_cmd($check), "/bin/echo TEST OK",
	"command renders properly checks with environment variables";

$check->{command} = "/nonexistent/check";
is NLMA::render_cmd($check), "/bin/echo 'UNKNOWN - plugin \"/nonexistent/check\" not found (-e)'; exit 3",
	"command rendering detects missing check commands";

$check->{command} = "/etc";
is NLMA::render_cmd($check), "/bin/echo 'UNKNOWN - plugin \"/etc\" not a file (-f)'; exit 3",
	"command rendering detects check commands that are not files";

$check->{command} = "/etc/shadow";
is NLMA::render_cmd($check), "/bin/echo 'UNKNOWN - plugin \"/etc/shadow\" not readable (-r)'; exit 3",
	"command rendering detects unreadable check commands";

$check->{command} = "/etc/passwd";
is NLMA::render_cmd($check), "/bin/echo 'UNKNOWN - plugin \"/etc/passwd\" not executable (-x)'; exit 3",
	"command rendering detects unexecutable check commands";

$check->{command} = "t/bin/echo TEST OK";
is NLMA::render_cmd($check, "."), "./t/bin/echo TEST OK", "relative command renders correctly with root path";

done_testing;
