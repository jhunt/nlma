package Nagios::Poller;

use warnings;
use strict;

use POSIX;
use Cwd qw(abs_path);
use Sys::Hostname qw(hostname);

use Time::HiRes qw(gettimeofday usleep);
use YAML;

use Log::Log4perl qw(:easy);
use Log::Dispatch::Syslog;

our $VERSION = '1.0';

sub MAX { my ($a, $b) = @_; ($a > $b ? $a : $b); }
sub MIN { my ($a, $b) = @_; ($a < $b ? $a : $b); }

$| = 1;

use constant TICK => 1000;

sub daemonize
{
	DEBUG("daemonizing");

	open STDIN,  "</dev/null" or die "daemonize: failed to reopen STDIN\n";
	open STDOUT, ">/dev/null" or die "daemonize: failed to reopen STDOUT\n";
	open STDERR, ">/dev/null" or die "daemonize: failed to reopen STDERR\n";

	chdir('/');

	exit if fork;
	exit if fork;

	usleep(1000) until getppid == 1;
}

sub schedule_check
{
	my ($check) = @_;


	if ($check->{started_at}) {
		$check->{next_run} = $check->{started_at} + $check->{interval};
	} else {
		$check->{next_run} = gettimeofday + $check->{interval};
	}
}

sub run_check
{
	my ($check) = @_;

	my ($readfd, $writefd);
	pipe $readfd, $writefd;

	my $pid = fork();
	if ($pid < 0) {
		ERROR("fork failed for check $check->{name}");
		return undef;
	}

	if ($pid == 0) {
		my $name = "check $check->{name}";
		close STDERR;
		open STDERR, ">&", \*ERRLOG or WARN("$name STDERR reopen failed: ignoring check error output");

		close STDOUT;
		open STDOUT, ">&", \*$writefd or ERROR("$name STDOUT reopen failed: cannot get check output");

		close $readfd;
		close STDIN;

		exec("/bin/sh", "-c", $check->{command}) or do {
			FATAL("$name exec failed: $!");
			exit 42;
		}
	}

	$check->{started_at} = gettimeofday;
	$check->{ended_at} = 0;

	$check->{soft_stop} = $check->{started_at} + $check->{timeout};
	$check->{hard_stop} = $check->{soft_stop} + 2;

	$check->{sigterm} = $check->{sigkill} = 0;

	close $writefd;
	$check->{pipe} = $readfd;
	$check->{pid}  = $pid;

	INFO("running check $check->{name} pid $pid");
	DEBUG("check $check->{name} started_at = $check->{started_at}, soft_stop = $check->{soft_stop}, hard_stop = $check->{hard_stop}");

	return 1;
}

sub reap_check
{
	my ($check, $status) = @_;
	$check->{ended_at} = gettimeofday;
	$check->{duration} = $check->{ended_at} - $check->{started_at};
	$check->{exit_status} = (WIFEXITED($status) ? WEXITSTATUS($status) : -1);

	schedule_check($check);

	$check->{pid} = -1;
	my $buf = "";
	my $n = read($check->{pipe}, $buf, 8192);
	close $check->{pipe};

	if (!defined $n) {
		ERROR("check $check->{name} encountered read error getting output: $!");
		return -1;
	}

	if ($check->{sigkill} || $check->{sigterm}) {
		$buf = "check timed out";
	}
	my @l = split /[\r\n]/, $buf, 2;
	$buf = shift @l;
	$check->{output} = $buf eq "" ? "(no check output)" : $buf;

	$check->{pipe} = undef;

	DEBUG("check $check->{name} exited $check->{exit_status} with output '$check->{output}'");
	return 0;
}

sub send_nsca
{
	my ($parent, $cmd, $host, @checks) = @_;
	my ($address, $port) = split(/:/, $parent);

	my @command = (split(/\s+/, $cmd), "-H", $address, "-p", $port);
	DEBUG("send_nsca: executing ", join(' ', @command));

	pipe NSCA_READ, NSCA_WRITE;

	my $pid = fork();
	if ($pid < 0) {
		ERROR("failed to fork off send_nsca");
		return -1;
	}

	if ($pid == 0) {
		close NSCA_WRITE;
		close STDIN;
		open(STDIN, "<&NSCA_READ") or FATAL("send_nsca failed to reopen STDIN: $!");
		exec(@command) or do {
			FATAL("exec send_nsca failed: $!");
			exit 42;
		}
	}

	DEBUG("send_nsca: child $pid forked");
	close NSCA_READ;
	for my $c (@checks) {
		DEBUG("send_nsca: write '".join("\t", $host, $c->{name}, $c->{exit_status}, $c->{output})."'");
		print NSCA_WRITE join("\t", $host, $c->{name}, $c->{exit_status}, $c->{output})."\n";
	}
	close NSCA_WRITE;

	return $pid;
}

sub parse_config
{
	my ($file) = @_;

	DEBUG("parsing configuration in $file");

	open CONFIG, $file or return undef;
	my $yaml = join('', <CONFIG>);
	close CONFIG;

	my ($config, $checks) = Load($yaml);
	if (!exists $config->{hostname}) {
		$config->{hostname} = hostname;
		DEBUG("no config for hostname: using detected value of $config->{hostname}");
	}
	if (!exists $config->{parents}) {
		DEBUG("no config for parents: using default of []");
		$config->{parents} = [];
	}
	if (!exists $config->{dump}) {
		$config->{dump} = "/var/tmp";
		DEBUG("no config for dump directory: using default of $config->{dump}");
	}
	$config->{dump} = abs_path($config->{dump});

	if (!exists $config->{errlog}) {
		$config->{errlog} = "/var/log/npoll_err";
		DEBUG("no config for errlog: using default of $config->{errlog}");
	}
	$config->{errlog} = abs_path($config->{errlog});

	if (!exists $config->{startup_splay}) {
		$config->{startup_splay} = 15;
		DEBUG("no config for startup_splay: using default of $config->{startup_splay} seconds");
	}

	$config->{log} = $config->{log} || {};
	if (!exists $config->{log}->{facility}) {
		$config->{log}->{facility} = 'daemon';
		DEBUG("no syslog facility configured: using default of $config->{log}->{facility}");
	}
	if (!exists $config->{log}->{level}) {
		$config->{log}->{level} = 'error';
		DEBUG("no syslog level configured: using default of $config->{log}->{level}");
	}

	my @list = ();
	for my $cname (keys %$checks) {
		DEBUG("parsed check definition for $cname");
		my $check = $checks->{$cname};
		$check->{name} = $cname;

		# Default timeout of 30s
		$check->{timeout} = $check->{timeout} || 30;

		# Default interval of 5 minutes
		$check->{interval} = $check->{timeout} || 300;

		DEBUG("$cname interval is $check->{interval} seconds");
		DEBUG("$cname timeout is $check->{timeout} seconds");
		DEBUG("$cname command is '$check->{command}'");

		push @list, $check;
	}

	# Stagger-schedule the first run, longest interval runs first
	@list = sort { $b->{interval} <=> $a->{interval} } @list;
	my $run_at = gettimeofday;
	for my $check (@list) {
		$check->{next_run} = $run_at;
		$run_at += $config->{startup_splay};
	}

	return $config, \@list;
}

sub dump_config
{
	my ($config, $checks) = @_;

	my $file = "$config->{dump}/npoll.".gettimeofday().".yml";
	INFO("dumping config+checks to $file");

	my $fh;
	if (open $fh, ">$file") {
		print $fh Dump($config, $checks);
		close $fh;
	} else {
		ERROR("failed to dump config to $file: $!");
	}
}

sub merge_check_defs
{
	my ($old, $new) = @_;

	DEBUG("merging check definitions: ".scalar(@$old)." old, ".scalar(@$new));

	for my $check (@$old) {
		$check->{reconfiguring} = 1;
	}

	my @add = ();

	for my $newcheck (@$new) {
		my $found = 0;
		for my $oldcheck (@$old) {
			next unless $oldcheck->{name} eq $newcheck->{name};
			$found = 1;

			$oldcheck->{command}  = $newcheck->{command};
			$oldcheck->{interval} = $newcheck->{interval};
			$oldcheck->{timeout}  = $newcheck->{timeout};

			DEBUG("updating check definition for $oldcheck->{name}");

			if ($oldcheck->{pid} <= 0) {
				DEBUG("check $oldcheck->{name} not running; rescheduling");
				schedule_check($oldcheck);
			}

			delete $oldcheck->{reconfiguring};
			last;
		}

		if (!$found) {
			DEBUG("adding check definition for $newcheck->{name}");
			push @add, $newcheck;
		}
	}

	for my $check (@$old) {
		next unless $check->{reconfiguring};

		DEBUG("deleting check definition for $check->{name}");

		delete $check->{reconfiguring};
		$check->{deleted} = 1;
	}

	push @$old, @add;
	return 0;
}

sub waitall
{
	my ($config, $checks, $flags) = @_;
	my @results = ();

	while ( (my $child = waitpid(-1, $flags)) > 0) {
		my $status = $?;

		my $found = 0;
		for my $check (@$checks) {
			next unless $check->{pid} == $child;

			$found = 1;
			DEBUG("reaping child check process $child");
			reap_check($check, $?);
			push @results, $check;
			last;
		}

		if (!$found) {
			DEBUG("reaping child send_nsca process $child");
		}
	}

	if (@results) {
		for my $parent (@{$config->{parents}}) {
			DEBUG("sending ".scalar(@results). " results to $parent");
			send_nsca($parent, $config->{send_nsca}, $config->{hostname}, @results);
		}
	}
}

sub configure_syslog
{
	my ($logcfg) = @_; # the 'log' key of config
	Log::Log4perl::init({
		'log4perl.rootLogger'                => "DEBUG,SYSLOG",
		'log4perl.appender.SYSLOG'           => "Log::Dispatch::Syslog",
		'log4perl.appender.SYSLOG.min_level' => $logcfg->{level} || "warning",
		'log4perl.appender.SYSLOG.ident'     => 'npoll',
		"log4perl.appender.SYSLOG.facility"  => $logcfg->{facility} || "daemon",
		'log4perl.appender.SYSLOG.layout'    => "Log::Log4perl::Layout::PatternLayout",
		'log4perl.appender.SYSLOG.layout.ConversionPattern' => "[%P] %m",
	});
}

my $RECONFIG = 0;
sub sighup_handler { $RECONFIG = 1; }

my $TERM = 0;
sub sigterm_handler { $TERM = 1; }

my $DUMPCONFIG = 0;
sub sigusr1_handler { $DUMPCONFIG = 1; }

sub start
{
	my ($class, $config_file, $foreground) = @_;

	$config_file = abs_path($config_file);
	if (!-r $config_file) {
		print STDERR "$config_file: $!\n";
		exit 1;
	}

	daemonize unless $foreground;
	my ($config, $checks) = parse_config($config_file);
	configure_syslog($config->{log}) unless $foreground;

	INFO("npoll v$VERSION starting up");

	open ERRLOG, ">>$config->{errlog}";

	$SIG{HUP}  = \&sighup_handler;
	$SIG{TERM} = \&sigterm_handler;
	$SIG{USR1} = \&sigusr1_handler;
	$SIG{PIPE} = "IGNORE";

	while (1) {
		last if $TERM;

		if ($RECONFIG) {
			INFO("SIGHUP caught; reconfiguring");
			$RECONFIG = 0;
			my ($newconfig, $newchecks) = parse_config($config_file);

			if ($newconfig->{errlog} ne $config->{errlog}) {
				close ERRLOG;
				open ERRLOG, ">>$newconfig->{errlog}";

			}
			$config = $newconfig;
			configure_syslog($config->{log}) unless $foreground;

			merge_check_defs($checks, $newchecks);
		}

		$checks = [grep { $_->{pid} > 0 || !exists $_->{deleted} } @$checks];

		if ($DUMPCONFIG) {
			$DUMPCONFIG = 0;
			INFO("SIGUSR1 caught; dumping config+checks");
			dump_config($config, $checks);
		}

		my $now = gettimeofday;
		for my $check (@$checks) {
			if ($check->{pid} > 0) {
				if ($check->{hard_stop} < $now && !$check->{sigkill}) {
					WARN("check $check->{name} pid $check->{pid} exceeded hard_stop; sending SIGKILL");
					$check->{sigkill} = 1;
					kill(KILL => $check->{pid});

				} elsif ($check->{soft_stop} < $now && !$check->{sigterm}) {
					WARN("check $check->{name} pid $check->{pid} exceeded soft_stop; sending SIGTERM");
					$check->{sigterm} = 1;
					kill(TERM => $check->{pid});

				}
			} else {
				next if $check->{deleted};

				if ($check->{next_run} < $now) {
					DEBUG("check $check->{name} next run $check->{next_run} < $now");
					run_check($check);
				}
			}
		}

		waitall($config, $checks, POSIX::WNOHANG);
		usleep(TICK);
	}

	if ($TERM) {
		INFO("SIGTERM caught; exiting");
		waitall($config, $checks);
	}
}

1;
