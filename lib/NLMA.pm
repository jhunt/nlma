package NLMA;

use warnings;
use strict;

use POSIX;
use Fcntl qw(LOCK_EX LOCK_NB);
use Cwd qw(abs_path);
use Sys::Hostname qw(hostname);
use File::Temp qw(tempfile);

use IO::Select;
use Time::HiRes qw(gettimeofday usleep);
use YAML;
use Hash::Merge qw(merge);

use Log::Log4perl qw(:easy);
use Log::Dispatch::Syslog;

my %STATE_CODES = (
	OK       => 0,
	WARNING  => 1,
	CRITICAL => 2,
	UNKNOWN  => 3,
);

my %LOCKS = ();
my $OOB_PREFIX = "oob";

our $VERSION = '2.15';

sub MAX { my ($a, $b) = @_; ($a > $b ? $a : $b); }
sub MIN { my ($a, $b) = @_; ($a < $b ? $a : $b); }

$| = 1;

# 50,000 microseconds = 0.05 seconds
use constant TICK => 50*1000;

# for check-in result
my @RUNTIMES = ();

sub clean_check_output
{
	my ($buf) = @_;

	# Drop carriage returns
	$buf =~ s/\r//mg;
	# Drop the last trailing newline
	$buf =~ s/\n$//m;

	return $buf;
}

sub render_cmd
{
	my ($check, $root, $debug) = @_;

	my $run_as  = $check->{sudo};
	my $command = $check->{command};

	$debug    = 0 unless defined $debug;
	$command .= ' -D'x$debug;

	if (substr($command, 0, 1) ne "/") {
		if ($root) {
			$command = "$root/$command";
		} else {
			WARN("check $check->{name} has relative command, but no plugin_root specified!!");
		}
	}

	# check for existence of plugin executable (but only for absolute paths)
	if ($command =~ m|^(/[^\s]*)|) {
		my $bin = $1;
		INFO("Checking $bin for -e, -f, -r and -x");
		my $error;
		if    (!-e $bin) { $error = "not found (-e)"      }
		elsif (!-f $bin) { $error = "not a file (-f)"     }
		elsif (!-r $bin) { $error = "not readable (-r)"   }
		elsif (!-x $bin) { $error = "not executable (-x)" }

		if ($error) {
			ERROR("executable for $check->{name} ($bin) $error");
			$command = "/bin/echo 'UNKNOWN - plugin \"$bin\" $error'; exit 3";

			# skip sudo, if specified (we don't need to sudo echo)
			$run_as = undef;
		}
	}

	if ($run_as) {
		my $env_string = join(" ", map { "$_=$check->{env}{$_}" } keys %{$check->{env}});
		$command = "/usr/bin/sudo -n -u $run_as $env_string /usr/bin/nlma-timeout -t $check->{timeout} -n '$check->{hostname}/$check->{name}' -- $command";
	}

	return $command;
}

sub drop_privs
{
	my ($user, $group) = @_;

	my $uid = getpwnam($user)  or die "User $user does not exist\n";
	my $gid = getgrnam($group) or die "Group $group does not exist\n";

	if ($) != $gid) {
		setgid($gid) || die "Could not setgid to $group group\n";
	}
	if ($> != $uid) {
		setuid($uid) || die "Could not setuid to $user user\n";
	}
}

sub daemonize
{
	my ($user, $group, $pid_file) = @_;

	DEBUG("daemonizing");

	open(SELFLOCK, "<$0") or die "Couldn't find $0: $!\n";
	flock(SELFLOCK, LOCK_EX | LOCK_NB) or die "Lock failed; is another nlma daemon running?\nShawn, are you sure you didn't mean to add the '-t' flag?\n";
	open(PIDFILE, ">$pid_file") or die "Couldn't open $pid_file: $!\n";

	drop_privs($user, $group);

	open STDIN,  "</dev/null" or die "daemonize: failed to reopen STDIN\n";
	open STDOUT, ">/dev/null" or die "daemonize: failed to reopen STDOUT\n";
	open STDERR, ">/dev/null" or die "daemonize: failed to reopen STDERR\n";

	chdir('/');

	exit if fork;
	exit if fork;

	usleep(1000) until getppid == 1;

	print PIDFILE "$$\n";
	close PIDFILE;
}

sub schedule_check
{
	my ($check, $interval) = @_;

	$interval ||= $check->{interval};
	if ($check->{is_soft_state}) {
		$interval = $check->{retry};
	}

	$check->{next_run} = ($check->{started_at} || gettimeofday) + $interval;
	DEBUG("scheduled $check->{name} to run in $interval s at $check->{next_run}");
}

sub run_check
{
	my ($check, $root, $debug) = @_;

	if (locked($check->{lock})) {
		INFO("check $check->{name} attempted to run, but is locked by " . keymaster()->{$check->{lock}}{locked_by});
		schedule_check($check, 5);
		return 1; # return 1, so the lock doesn't get undone, as this is not an error running the check,
		          # but rather desired behavior
	} else {
		if($check->{lock}) {
			INFO("locking $check->{lock} for execution of $check->{name}");
			NLMA::lock($check->{lock}, locked_by => $check->{name});
		}
	}

	my ($readfd, $writefd);
	pipe $readfd, $writefd;

	my $command = render_cmd($check, $root, $debug);

	INFO("executing '$command' via /bin/sh -c");

	$check->{output} = '';

	(my $fh, $check->{stderr_out}) = tempfile();
	close $fh; # don't need the file handle, just the filename

	my $pid = fork();
	if ($pid < 0) {
		ERROR("fork failed for check $check->{name}");
		return undef;
	}

	if ($pid == 0) {
		my $name = "check $check->{name}";

		open STDERR, ">", $check->{stderr_out} or WARN("$name STDERR reopen failed: ignoring check error output");
		open STDOUT, ">&", \$writefd or ERROR("$name STDOUT reopen failed: cannot get check output");
		open STDIN, "</dev/null" or ERROR("Failed to reopen STDIN: $!");
		close $readfd;

		$ENV{$_} = $check->{env}{$_} for keys %{$check->{env}};
		exec("/bin/sh", "-c", $command) or do {
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
	unlock($check->{lock}) if $check->{lock};
	$check->{ended_at} = gettimeofday;
	$check->{duration} = $check->{ended_at} - $check->{started_at};
	$check->{exit_status} = (WIFEXITED($status) ? WEXITSTATUS($status) : -1);

	push @RUNTIMES, $check->{duration};

	read_all($check);

	if ($check->{sigkill} || $check->{sigterm}) {
		$check->{output} = "check timed out (exceeded NLMA timeout)";
		$check->{exit_status} = $STATE_CODES{$check->{on_timeout}};
	}
	$check->{output} = clean_check_output($check->{output});

	## read STDERR
	$check->{stderr} = '';
	if (exists($check->{stderr_out}) && open(my $fh, '<', $check->{stderr_out})) {
		while (<$fh>) {
			$check->{stderr} .= $_;
			chomp;
			ERROR("STDERR($check->{name}): $_");
		}
		close $fh;
		unlink $check->{stderr_out};
		#delete $check->{stderr_out};
	} else {
		ERROR("check $check->{name} failed to read in STDERR file");
	}

	# if the plugin did not produce output to STDOUT, force
	# an UNKNOWN state; something amy be wrong with the plugin...
	if (!$check->{output}) {
		$check->{exit_status} = $STATE_CODES{UNKNOWN};

		# Use STDERR if it is available.
		if ($check->{output} = clean_check_output($check->{stderr})) {
			# minor fixups to make certain errors more... troubleshootable
			(my $bin = $check->{command}) =~ m/^([^\s]*)/;
			$check->{output} =~ s|^sudo: sorry, a password is required to run sudo$|sudo: failed to run $bin without a password, check /etc/sudoers (and puppet)!|;

			$check->{output} = "ERROR: $check->{output}";
		}
	}

	if (!$check->{output}) {
		$check->{output} = "(no check output)";
	}

	# calculate hard / soft state (for retry logic)
	$check->{last_state} = $check->{state} unless $check->{is_soft_state};
	$check->{state} = $check->{exit_status};
	if ($check->{state} < 0 || $check->{state} > 3) {
		$check->{state} = 3; # UNKNOWN
	}

	$check->{current}++;
	# OK != soft; propagation of previous state != soft
	if ($check->{state} == 0 || $check->{state} == $check->{last_state}) {
		$check->{is_soft_state} = 0;
		$check->{current} = 1;

	} elsif ($check->{current} >= $check->{attempts}) {
		$check->{is_soft_state} = 0;
		$check->{current} = 1;

	} else {
		$check->{is_soft_state} = 1;
	}

	DEBUG("check $check->{name} :: last_state:$check->{last_state}, state:$check->{state}, attempts:$check->{current}/$check->{attempts}, soft:$check->{is_soft_state}");
	schedule_check($check);
	$check->{pid} = -1;

	DEBUG("check $check->{name} exited $check->{exit_status} with output '$check->{output}'");
	return 0;
}

sub filter_checks
{
	my ($checks, $q, $re) = @_;
	$re = '.' unless $re;
	$q = 'default' unless $q;
	my %Q = map { $_ => 1 } split /\s*,\s*/, $q;
	return [grep { ($Q{all} || $Q{$_->{group}}) && $_->{name} =~ $re } @$checks];
}

sub send_nsca
{
	my ($parent, $cmd, @checks) = @_;
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
		open STDIN, "<&NSCA_READ" or FATAL("send_nsca failed to reopen STDIN: $!");
		open STDOUT, ">/dev/null" or FATAL("send_nsca failed to reopen STDOUT: $!");
		open STDERR, ">/dev/null" or FATAL("send_nsca failed to reopen STDERR: $!");

		exec(@command) or do {
			FATAL("exec send_nsca failed: $!");
			exit 42;
		}
	}

	DEBUG("send_nsca: child $pid forked");
	close NSCA_READ;
	for my $c (@checks) {
		DEBUG("send_nsca: write '".join("\t", $c->{hostname}, $c->{name}, $c->{exit_status}, $c->{output})."'");
		print NSCA_WRITE join("\t", $c->{hostname}, $c->{name}, $c->{exit_status}, $c->{output})."\n\x17";
	}
	close NSCA_WRITE;

	return 0 if waitpid($pid, POSIX::WNOHANG) == $pid;
	DEBUG("send_nsca not terminating... waiting for up to 2 seconds");

	sleep(1);
	return 0 if waitpid($pid, POSIX::WNOHANG) == $pid;

	sleep(1);
	return 0 if waitpid($pid, POSIX::WNOHANG) == $pid;

	WARN("KILLING send_nsca process bound for $address:$port");
	kill(9, $pid);
	return 0;
}

sub slurp
{
	my ($file) = @_;
	open my $fh, "<", $file or return undef;
	my $s = do { local $/; <$fh> };
	close $fh;
	return $s;
}

sub parse_config
{
	my ($file) = @_;
	my $inc_dir = $file; $inc_dir =~ s/[^\/]*$//;

	DEBUG("parsing configuration in $file");

	my $yaml = slurp($file) or return undef;
	my ($config, $checks) = eval { Load($yaml) } or return undef;
	$config->{startup}  = gettimeofday unless $config->{startup};
	$config->{version}  = $NLMA::VERSION;
	$config->{warnings} = [];
	$config->{errors}   = [];

	if (!exists $config->{hostname}) {
		$config->{hostname} = hostname;
		DEBUG("no config for hostname: using detected value of $config->{hostname}");
	}
	if (!exists $config->{user}) {
		$config->{user} = "icinga";
		DEBUG("no config for daemon user: using default of $config->{user}");
	}
	if (!exists $config->{group}) {
		$config->{group} = "icinga";
		DEBUG("no config for daemon group: using default of $config->{group}");
	}
	if (!exists $config->{pid_file}) {
		$config->{pid_file} = "/var/run/nlma.pid";
		DEBUG("no config for pid file: using default of $config->{pid_file}");
	}
	if (!exists $config->{parents}) {
		DEBUG("no config for parents: using default of {}");
		$config->{parents} = {default => []};
	} elsif (!exists $config->{parents}{default}) {
		DEBUG("no config for parents[default]: using default of []");
		$config->{parents}{default} = [];
	}
	if (!exists $config->{send_nsca}) {
		$config->{send_nsca} = "/usr/bin/send_nsca -c /etc/icinga/send_nsca.cfg";
		DEBUG("no config for send_nsca: using default of $config->{send_nsca}");
	}
	if (!exists $config->{timeout}) {
		$config->{timeout} = 30;
		DEBUG("no config for timeout: using default of $config->{timeout}s");
	}
	if (!exists $config->{on_timeout}) {
		$config->{on_timeout} = "CRITICAL";
		DEBUG("no config for on_timeout: using default of $config->{on_timeout}");
	} else {
		$config->{on_timeout} = uc($config->{on_timeout});
		if ($config->{on_timeout} !~ m/^(WARNING|CRITICAL|UNKNOWN)/) {
			WARN("$config->{on_timeout} is not an acceptable on_timeout value; falling back to default of 'CRITICAL'");
			$config->{on_timeout} = "CRITICAL";
		}
	}
	if (!exists $config->{interval}) {
		$config->{interval} = 300;
		DEBUG("no config for interval: using default of $config->{interval}s");
	}

	if (!exists $config->{plugin_root}) {
		DEBUG("no plugin_root configured; all check commands must be absolute paths!");
	}
	if (!exists $config->{dump}) {
		$config->{dump} = "/var/tmp";
		DEBUG("no config for dump directory: using default of $config->{dump}");
	}
	$config->{dump} = abs_path($config->{dump});

	if (!exists $config->{startup_splay}) {
		$config->{startup_splay} = 0;
		DEBUG("no config for startup_splay: using default (auto-calculate)");
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

	$config->{checkin} = $config->{checkin} || {};
	if (!exists $config->{checkin}->{interval}) {
		$config->{checkin}->{interval} = 300;
		DEBUG("no config for checkin interval: using default of $config->{checkin}->{interval}");
	}
	if (!exists $config->{checkin}->{service}) {
		$config->{checkin}->{service} = "nlma_checkin";
		DEBUG("no config for checkin service: using default of $config->{checkin}->{service}");
	}

	if (exists $config->{include}) {
		# Allow single include
		$config->{include} = [$config->{include}] unless ref($config->{include}) eq 'ARRAY';

		for my $file (@{$config->{include}}) {
			my $inc_file = $file;
			$inc_file = "$inc_dir/$file" unless substr($file,0,1) eq '/';
			DEBUG("Including $inc_file");

			$yaml = slurp($inc_file);
			unless ($yaml) {
				push @{$config->{errors}}, "Failed to read $file";
				ERROR("Failed to read file $inc_file: $!");
				next;
			}

			my $new_checks;
			eval {
				$new_checks = Load($yaml);
				1;
			} or do {
				push @{$config->{errors}}, "Failed to parse $file";
				ERROR("Failed to parse file $inc_file: $@");
				next;
			};
			for my $cname (keys %$new_checks) {

				if (exists $checks->{$cname}) {
					# Uh-oh, someone tried to redefine a check
					# Log it as an error, ignore the override and send a Warning to SFR
					push @{$config->{warnings}}, "Attempted to redefine '$cname' check in $file";
					ERROR("Attempted to redefine '$cname' check in $inc_file");

				} else {
					$checks->{$cname} = $new_checks->{$cname};
				}
			}
		}

		delete $config->{include};
	}

	my $min_interval = 300;

	my @list = ();
	for my $cname (keys %$checks) {
		DEBUG("parsed check definition for $cname");
		my $check = $checks->{$cname};
		if (!$check || ref($check) ne 'HASH' || !exists $check->{command}) {
			ERROR("check '$cname' is missing command definition");
			return undef;
		}
		$check->{env} = merge($check->{env} || {}, $config->{env}); # environment variables
		$check->{current} = 1; # current attempt

		# Use config key as name if not overridden
		$check->{name} = $check->{name} || $cname;

		# Default timeout of 30s
		$check->{timeout} = $check->{timeout} || $config->{timeout};
		$check->{on_timeout} = $config->{on_timeout};

		# Default interval of 5 minutes
		$check->{interval} = $check->{interval} || $config->{interval};

		# Default attempts of 1
		$check->{attempts} = $check->{attempts} || 1;

		# Default retry of 1 minute
		$check->{retry} = $check->{retry} || 60;

		# Use default check environment
		$check->{environment} = $check->{environment} || 'default';
		$check->{env}{MONITOR_FEEDER_TARGETS} ||=
			join(',', @{$config->{parents}{$check->{environment}}})
				if $config->{parents}{$check->{environment}};

		# Use default check group
		$check->{group} = $check->{group} || 'default';

		# Use global host definition by default
		$check->{hostname} = $check->{hostname} || $config->{hostname};

		$cname = "$check->{group}/$cname";
		DEBUG("$cname name is '$check->{name}'");
		DEBUG("$cname group is '$check->{group}'");
		DEBUG("$cname environment is '$check->{environment}'");
		DEBUG("$cname command is '$check->{command}'");
		DEBUG("$cname interval is $check->{interval} seconds");
		DEBUG("$cname timeout is $check->{timeout} seconds");
		DEBUG("$cname attempts is $check->{attempts}");
		DEBUG("$cname retry interval is $check->{retry} seconds");
		DEBUG("$cname env $_='$check->{env}{$_}'") for sort keys %{$check->{env}};

		$check->{started_at} = $check->{duration} = $check->{ended_at} = 0;
		$check->{next_run} = 0;
		$check->{current} = $check->{is_soft_state} = 0;
		$check->{last_state} = $check->{state} = 0;
		$check->{pid} = $check->{exit_status} = -1;
		$check->{output} = "";

		$min_interval = MIN($min_interval, $check->{interval});

		push @list, $check;

		$config->{groups}{$check->{group}}{name} = $check->{group}; # auto-vivify!
		$config->{groups}{$check->{group}}{count}++;

		if (!exists $config->{groups}{$check->{group}}{min_interval}) {
			$config->{groups}{$check->{group}}{min_interval} = $check->{interval};
		}

		$config->{groups}{$check->{group}}{min_interval} = MIN(
			$config->{groups}{$check->{group}}{min_interval},
			$check->{interval}
		);
	}

	# Stagger-schedule the first run, longest interval runs first
	@list = sort { $b->{interval} <=> $a->{interval} } @list;

	my $START = gettimeofday;
	for my $group (values %{$config->{groups}}) {
		next unless $group->{count};

		if (!exists $group->{splay}) {
			$group->{splay} = $config->{startup_splay};
			INFO("Falling back to default splay of $group->{splay} for $group->{name} checks");
		}

		if ($group->{splay} <= 0) {
			$group->{splay} = $group->{min_interval} / $group->{count};
			INFO("Auto-calculated splay for $group->{name} checks as $group->{count}/$group->{min_interval} == $group->{splay}");
		}

		my $run_at = $START;
		for my $check (@list) {
			next unless $check->{group} eq $group->{name};
			$check->{next_run} = $run_at;
			$run_at += $group->{splay};
		}
	}

	return $config, \@list;
}

sub dump_config
{
	my ($config, $checks) = @_;

	my $file = "$config->{dump}/nlma.".gettimeofday().".yml";
	INFO("dumping config+checks to $file");

	$config->{lastdump} = gettimeofday;
	$config->{locks} = \%LOCKS;

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
			next unless $oldcheck->{hostname} eq $newcheck->{hostname};
			$found = 1;

			for (qw(environment group
					sudo lock env
					command timeout on_timeout
					interval retry attempts)) {
				next unless $newcheck->{$_};
				$oldcheck->{$_} = $newcheck->{$_}
			}
			for (qw(sudo lock)) {
				delete $oldcheck->{$_} unless $newcheck->{$_};
			}

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

sub read_once
{
	my ($check) = @_;
	return 0 unless $check->{pipe};

	my $tmp = '';
	my $n = read($check->{pipe}, $tmp, 8192);

	if (!defined $n) {
		ERROR("check $check->{name} encountered read error getting output: $!");
		return 0;
	}

	if ($n == 0) {
		DEBUG("EOF for $check->{name} pid $check->{pid}; closing pipe");
		close $check->{pipe};
		$check->{pipe} = undef;
		return 0;
	}

	if (length($check->{output}) >= 4096) {
		DEBUG("Read $n bytes from $check->{name} pid $check->{pid} - discarding (already have ".length($check->{output})." bytes)");
	} else {
		DEBUG("Read $n bytes from $check->{name} pid $check->{pid}");
		$check->{output} = substr($check->{output}.$tmp, 0, 4096);
	}

	return 1;
}

sub read_all
{
	my ($check) = @_;
	while (read_once($check)) { }
}

sub waitall
{
	my ($config, $checks, $flags) = @_;
	my %results = ();

	# First, we try to read from any and all child pipes
	# until we exhaust readable pipes
	#
	my %lookup = map { $_->{pipe} => $_ } grep { $_->{pipe} } @$checks;
	my (@readable, @pipes);

	do {
		@pipes = grep { $_ } map { $_->{pipe} } @$checks;
		@readable = IO::Select->new(@pipes)->can_read(0);
		read_once($lookup{$_}) for @readable;
	} while @readable;

	# Then, we see if any child wants to terminate,
	# without blocking if $flags == POSIX::WNOHANG

	while ( (my $child = waitpid(-1, $flags || 0)) > 0) {
		my $status = $?;

		my $found = 0;
		for my $check (@$checks) {
			next unless $check->{pid} == $child;

			$found = 1;
			DEBUG("reaping child check process $child");
			reap_check($check, $?);
			unless ($check->{is_soft_state}) {
				my $env = $check->{environment};
				$results{$env} = [] unless $results{$env};
				push @{$results{$env}}, $check;
			}
			last;
		}

		if (!$found) {
			DEBUG("reaping child send_nsca process $child");
		}
	}

	for my $env (keys %results) {
		for my $parent (@{$config->{parents}{$env}}) {
			DEBUG("sending ".scalar(@{$results{$env}}). " results to $parent");
			send_nsca($parent, $config->{send_nsca}, @{$results{$env}});
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
		'log4perl.appender.SYSLOG.ident'     => 'nlma',
		"log4perl.appender.SYSLOG.facility"  => $logcfg->{facility} || "daemon",
		'log4perl.appender.SYSLOG.layout'    => "Log::Log4perl::Layout::PatternLayout",
		'log4perl.appender.SYSLOG.layout.ConversionPattern' => "[%P] %m",
	});
}

sub checkin
{
	my ($config) = @_;

	my $total_time = 0;
	my $avg_time = 0;
	my $nchecks = 0;

	if (@RUNTIMES) {
		for my $runtime (@RUNTIMES) {
			$total_time += $runtime
		}
		$nchecks = @RUNTIMES;
		$avg_time = sprintf("%.3f", $total_time / $nchecks);
	}

	my $perfdata = "nchecks=$nchecks;;;; avgTime=$avg_time;;;;";

	my $fake_check = {
		hostname => $config->{hostname},
		name => $config->{checkin}->{service},
		exit_status => $STATE_CODES{OK},
		output => "$nchecks checks run, ${avg_time}s average runtime",
	};

	if (@{$config->{errors}}) {
		$fake_check->{exit_status} = $STATE_CODES{CRITICAL};
		$fake_check->{output} = join('.  ', @{$config->{errors}});

	} elsif (@{$config->{warnings}}) {
		$fake_check->{exit_status} = $STATE_CODES{WARNING};
		$fake_check->{output} = join('.  ', @{$config->{warnings}});
	}

	$fake_check->{output} .= "| $perfdata";
	DEBUG("CHECKIN - $fake_check->{hostname}/$fake_check->{name} ($fake_check->{exit_status}): $fake_check->{output}");

	for my $parent (@{$config->{parents}{default}}) {
		send_nsca($parent, $config->{send_nsca}, $fake_check);
	}

	@RUNTIMES = ();
}

our $RECONFIG = 0;
sub sighup_handler { $RECONFIG = 1; }

our $TERM = 0;
sub sigterm_handler { $TERM = 1; }

our $DUMPCONFIG = 0;
sub sigusr1_handler { $DUMPCONFIG = 1; }

sub runall
{
	my ($class, $config, $checks, $noop, $debug) = @_;

	my %results = ();
	for my $check (@$checks) {
		print "$check->{name}\n";
		print "   `$check->{command}`\n";
		if (! run_check($check, $config->{plugin_root}, $debug)) {
			# Remove locks if we failed to run the check
			unlock($check->{lock}) if $check->{lock};
		}
		read_all($check);
		waitpid($check->{pid}, 0);
		reap_check($check, $?);
		print "   OUTPUT: '$check->{output}'\n";
		print "\n";
		push @{$results{$check->{environment}}}, $check;
	}

	return if $noop;
	for my $env (keys %results) {
		for my $parent (@{$config->{parents}{$env}}) {
			print "NSCA: $env \@$parent\n";
			for my $check (@{$results{$env}}) {
				print "   $check->{name}\n";
			}
			send_nsca($parent, $config->{send_nsca}, @{$results{$env}});
		}
	}
}

sub submit_oob
{
	my ($class, $config_file, $alert) = @_;
	$config_file = abs_path($config_file);
	if (!-r $config_file) {
		print STDERR "$config_file: $!\n";
		exit 1;
	}

	my ($config, undef) = parse_config($config_file);
	INFO "nlma v$VERSION starting up (running as $>:$))\n";

	my $service = "${OOB_PREFIX}_".$alert->{service};
	$service =~ s/^(${OOB_PREFIX}_)${OOB_PREFIX}_/$1/; # de-dupe prefixes
	my $check = {
		hostname    => $alert->{host},
		name        => $service,
		exit_status => $alert->{code},
		output      => "$alert->{output} (submitted via $config->{hostname})",
	};
	$check->{hostname} = $config->{hostname} unless $check->{hostname};

	my $env = 'default';
	for my $parent (@{$config->{parents}{$env}}) {
		INFO "NSCA: $env \@$parent\n";
		send_nsca($parent, $config->{send_nsca}, $check);
	}
}

sub start
{
	my ($class, $config_file, $foreground) = @_;

	$config_file = abs_path($config_file);
	if (!-r $config_file) {
		print STDERR "$config_file: $!\n";
		exit 1;
	}

	my ($config, $checks) = parse_config($config_file);
	if (!$config) {
		print STDERR "$config_file: bad configuration file (check YAML syntax)\n";
		exit 1;
	}

	daemonize($config->{user}, $config->{group}, $config->{pid_file}) unless $foreground;
	configure_syslog($config->{log}) unless $foreground;

	INFO("nlma v$VERSION starting up");
	INFO("configured to run ",scalar @$checks," checks");

	$SIG{HUP}  = \&sighup_handler;
	$SIG{TERM} = \&sigterm_handler;
	$SIG{USR1} = \&sigusr1_handler;
	$SIG{PIPE} = "IGNORE";

	my $next_checkin = gettimeofday + $config->{checkin}->{interval};
	while (1) {
		last if $TERM;

		if ($RECONFIG) {
			INFO("SIGHUP caught; reconfiguring");
			$RECONFIG = 0;
			my ($newconfig, $newchecks) = parse_config($config_file);
			if (!$newconfig) {
				ERROR("Failed to parse $config_file; ignoring SIGHUP reload request");

			} else {
				# Do any new-config, old-config transitional tasks

				$config = $newconfig;
				configure_syslog($config->{log}) unless $foreground;

				merge_check_defs($checks, $newchecks);
			}
		}

		$checks = [grep { $_->{pid} > 0 || !exists $_->{deleted} } @$checks];

		if ($DUMPCONFIG) {
			$DUMPCONFIG = 0;
			INFO("SIGUSR1 caught; dumping config+checks");
			dump_config($config, $checks);
		}

		my $now = gettimeofday;
		if ($next_checkin < $now) {
			checkin($config);
			$next_checkin += $config->{checkin}->{interval};
		}
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
					if (!run_check($check, $config->{plugin_root})) {
						# Remove locks if we failed to run the check
						unlock($check->{lock}) if $check->{lock};
					}
				}
			}
		}

		waitall($config, $checks, POSIX::WNOHANG);
		usleep(TICK);
	}

	if ($TERM) {
		INFO("SIGTERM caught; exiting");
		# Reap child processes that are ready to go
		waitall($config, $checks, POSIX::WNOHANG);

		# Anyone else must be forcibly killed
		for my $check (@$checks) {
			next if $check->{pid} <= 0;

			INFO("killing $check->{name} pid $check->{pid} with SIGKILL");
			kill(KILL => $check->{pid});
			waitpid($check->{pid}, 0);
		}
	}
}

sub lock
{
	my ($key, %opts) = @_;
	return 0 unless $key;
	if (! locked($key)) {
		if (!exists $LOCKS{$key}) {
			$LOCKS{$key} = {
				%opts,
				unlocked_at => -1,
			};
		}
		$LOCKS{$key}{locked}    = 1;
		$LOCKS{$key}{locked_at} = time;
		return 1;
	} else {
		return 0;
	}
}

sub unlock
{
	my ($key) = @_;
	return unless $key;
	$LOCKS{$key}{locked} = 0;
	$LOCKS{$key}{unlocked_at} = time;
}

sub locked
{
	my ($key) = @_;
	return 0 unless $key;
	if ( exists $LOCKS{$key} && exists $LOCKS{$key}{locked}) {
		return $LOCKS{$key}{locked};
	} else {
		return 0;
	}
}

sub keymaster
{
	return \%LOCKS;
}

1;

=head1 NAME

NLMA - NLMA Local Monitoring Agent

=head1 DESCRIPTION

The NLMA module implements the guts of the B<nlma> command.
Administrators looking to configure or use nlma should see nlma(1).

=head1 METHODS

=over

=item B<start($class, $config_file, $foreground)>

Initiates the NLMA scheduling loop, like this:

  NLMA->start("/etc/nlma.yml")

The $config_file argument will be turned into an absolute path if it
is not, so that SIGHUP reconfiguration still works when daemonized
(and CWD has changed to /).

Normal startup problems (i.e. unreadable / non-existent configuration
file) are caught early, and cause the process to exit with an exit code
of 1.

If $foreground is passed, and is a true value, the poller will run in
so-called "foreground" mode; all logging is done to stderr and the
process does not fork into the background.  See nlma(1) for details.

=item B<runall($class, $config_file)>

Ignore scheduling and run all configured checks, for testing.

  NLMA->runall("/etc/nlma.yml")

After each check has been run, it will not be re-scheduled.

=item B<submit_oob($class, $config_file, $alert)>

Submits a single check result, out-of-band.  This is used primarily
by the B<alert> utility for shell scripts and other code to integrate
with monitoring.

  NLMA->submit_oob("/etc/nlma.yml", {
      host     => undef, # can be overridden
      service  => 'mlb_ripper',
      code     => 1
      output   => 'check output',
  });

Normally, the B<host> option doesn't need to be specified; NLMA
will fill in the auto-detected local hostname for you.  The option is
there to allow override an on-behalf-of submission.

B<NOTE>: no validation is done against the B<code> option.  Callers
are responsible for passing valid plugin exit codes (0,1,2 or 3).

The output that actually gets submitted up to the NSCA parents will
be prefixed with 'CLI: ', and suffixed with ' (submitted via $localhost)',
where I<$localhost> is the auto-detected local fqdn.

This helps prevent abuse of OOB submission to clear actual problems
by submitting forged results.

=back

=head1 INTERNAL METHODS

=over

=item B<clean_check_output($s)>

Handle extraneous whitespace and miscellaneous fixups to check output.

=item B<MAX($a, $b)>

Return the greater of two values.

=item B<MIN($a, $b)>

Return the lesser of two values.

=item B<daemonize>

Daemonize the process by forking into the background, closing all
file descriptors, and becoming a child of init(1)

=item B<schedule_check($check)>

Update the B<next_run> time for a check, based on the last time it
started execution, and its interval.

=item B<drop_privs($user, $group)>

Attempts to drop user privileges by switching the effective UID and
GID to the passed user and group.  If the process is already executing
under those effective IDs, setuid and/or setgid are not called.

=item B<render_cmd($check, $root, $debug)>

Take a check, and generate the comand to be run by NLMA.

Performs heuristics to ensure the command is in fact runnable.

If the check has been configured to run via sudo, the appropriate
sudo invocation (complete with -n) is constructed.

If $root is specified, it will be used as an absolute path to
prepend relative path command definitions.

=item B<run_check($check, $root)>

Fork a child process, with a uni-directional pipe, and execute the
check plugin command.  This function is responsible for keeping
track of the child process' PID, and setting up the soft and hard
timeout deadlines.

=item B<reap_check($check, $status)>

Perform necessary accounting actions, like calculating check duration
and determining child output and exit code.  The $status variable
should come from the waitpid call, and tells reap_check if the check
exited of its own accord, or was killed (either by the Agent, or
some other signal).

This function handles various edge cases, including check runs that
created no output, and check runs that were killed because of timeouts.

=item B<filter_checks($checks, $query)>

Given a set of checks, filter them to a subset, based on an arbitrary,
comma-separated list of groups.  The keywords B<default> and B<all> have
special meaning; B<default> matches checks without a group (and any that
are explicitly placed in the C<default> group).  B<all> matches all
checks, regardless of their grouping.

=item B<send_nsca($parent, $cmd, @checks)>

Fork a child process to submit results to a single Nagios parent via
send_nsca (specified by $cmd).

=item B<slurp($file)>

Slurp the entire contents of a file into memory, and return it,
or return B<undef> if an error condition occurs.

=item B<parse_config($file)>

Parse the NLMA YAML configuration, supplying default values
where appropriate.  Returns two values, the global configuration and
an array of normalized check definitions.

If any errors are encountered parsing the file, B<undef> will be
returned.  Callers should check this before doing anything with the
configuration (like trying to reconfigure on a live run)

=item B<dump_config($config, $checks)>

Dump configuration and scheduling data (usually in response to
SIGUSR1).  This function handles naming and creation of the dump
file.

=item B<merge_check_defs($old, $new)>

Merges check definitions (usually in response to reconfiguration via
SIGHUP).  This function handles the various edge cases to ensure
that check additions, updates and removals are processed properly,
even if a check is currently running.  $old and $new are array refs.

=item B<waitall($config, $checks, $flags)>

A refactoring, waitall waits for child processes to exit (either
check runs or send_nsca calls) and reacts accordingly.  Nothing is
done in response to a send_nsca child process terminating, but
check process termination is handled via a call to reap_check and
send_nsca.

The $flags arguments should either be undef, or POSIX::WNOHANG,
depending on whether it should wait for all child processes (i.e.
when terminating via SIGTERM) or just child processes that have
already exited (i.e. normal operation).

waitall will also perform select-based IO multiplexing on all live
child process output pipes, clearing out pipes and storing up to the
first 4k of output for each check.  This allows NLMA to handle plugins
that generate vast amounts of output, without deadlock.

See B<read_once>

=item B<read_all($check)>

Read from a child process output pipe, until the pipe is closed or an
error is detected.

This function is based off of B<read_once>, and is called from
B<reap_check> and B<runall> (for `nlma -tv`, which doesn't call the
B<waitall> function and therefore needs to read child output to prevent
deadlock).

=item B<read_once($check)>

Reads at most 8192 bytes from a child process output pipe.  If EOF or
an error condition is encountered, returns 0 to indicate that there is
no more to read.  Otherwise, returns 1.

=item B<configure_syslog($logcfg)>

Configures the Log::Log4perl subsystem to send log messages to the
appropriate syslog facility.  Used at startup and during SIGHUP
reconfiguration (unless the Agent is running in foreground mode).

=item B<checkin($config)>

Run the built-in poller checkin logic, to report back to all parent
instances that the poller is in fact running, and to show what it
has been doing since it last checked in (number of checks run,
average run time, etc.).

=item B<sighup_handler>

=item B<sigterm_handler>

=item B<sigusr1_handler>

Signal handles for dealing with external control mechanisms.

=item B<lock>

Creates a named mutex for locking checks to prevent them from running simultaneously.

Takes a mandatory lock name, followed by an optional hash to set custom lock attributes,
such as 'locked_by'.

=item B<locked>

Takes a mandatory lock name, and returns true or false whether or not it is currently
locked.

=item B<unlock>

Takes a mandatory lock name, and unlocks it.

=item B<keymaster>

Returns a hashref of the entire lock structure. This should contain what is actively
locked, when it was locked, and what check it was locked by.

=back

=head1 AUTHOR

NLMA was written by James Hunt <jhunt@synacor.com>

=head1 LICENSE

Copyright 2011-2014 Synacor, Inc.

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see L<http://www.gnu.org/licenses/>.

=cut
