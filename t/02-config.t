#!perl

use Test::More;
use Test::Deep;
use NLMA;

use Sys::Hostname qw(hostname);

{ # Default Configuration
	my ($config, $checks) = NLMA::parse_config('t/data/config/empty.yml');

	is($config->{hostname},  hostname, "<hostname> defaults to current node hostname");
	is($config->{user},      "icinga", "<user> default");
	is($config->{group},     "icinga", "<group> default");
	is($config->{pid_file},  "/var/run/nlma.pid", "<pid_file> default");
	is($config->{send_nsca}, "/usr/bin/send_nsca -c /etc/icinga/send_nsca.cfg", "<send_nsca> default");
	is($config->{timeout},   30, "<timeout> default");
	is($config->{interval},  300, "<interval> default");
	is($config->{startup_splay}, 0, "<startup_splay> default");
	is($config->{dump},      "/var/tmp", "<dump> default");
	is($config->{on_timeout}, "CRITICAL"),

	is_deeply($config->{log}, {
			level => 'error',
			facility => 'daemon',
		}, "<log> default");
	is_deeply($config->{checkin}, {
			service => 'nlma_checkin',
			interval => 300,
		}, "<checkin> default");
	is_deeply($config->{parents}, {
			default => [],
		}, "<parents> default");
}

{ # Overridden Configuration
	my ($config, $checks) = NLMA::parse_config('t/data/config/full.yml');

	is($config->{hostname},  'fixed.host.example.com', "<hostname> override");
	is($config->{user},      "mon-user", "<user> override");
	is($config->{group},     "mon-group", "<group> override");
	is($config->{pid_file},  "/path/to/pid.file", "<pid_file> override");
	is($config->{send_nsca}, "/opt/other/send_nsca -c /etc/nsca.cfg", "<send_nsca> override");
	is($config->{timeout},   75, "<timeout> override");
	is($config->{interval},  240, "<interval> override");
	is($config->{startup_splay}, 17, "<startup_splay> override");
	is($config->{dump},      "/usr/share", "<dump> override");
	is($config->{on_timeout}, "WARNING"),

	is_deeply($config->{log}, {
			level => 'info',
			facility => 'authpriv',
		}, "<log> override");
	is_deeply($config->{checkin}, {
			service => 'whats-up',
			interval => 123,
		}, "<checkin> override");
	is_deeply($config->{parents}, {
			default => [
				'df01.example.com',
				'df02.example.com',
			]
		}, "<parents> override");
}

{ # Bad On-Timeout Value ('OK' not an acceptable state)
	my ($config, $checks) = NLMA::parse_config('t/data/config/bad_ontimeout.yml');
	is($config->{on_timeout}, "CRITICAL"),
}

{ # Bad On-Timeout Value (not a real state)
	my ($config, $checks) = NLMA::parse_config('t/data/config/bad_ontimeout2.yml');
	is($config->{on_timeout}, "CRITICAL"),
}

{ # No default parents
	my ($config, $checks) = NLMA::parse_config('t/data/config/no-default-parents.yml');

	# Verify that if we specify parents, but forget the 'default' parents,
	# parse_config will Do The Right Thing (TM)

	is_deeply($config->{parents}, {
			default => [],
			prod => [
				'prod01.example.com',
				'prod02.example.com',
			],
			staging => [
				'stage01.example.com',
			],
		}, "<parents> default");
}

{ # Bad config file
	my ($config, $checks) = NLMA::parse_config('/path/to/nowhere');
	ok(!$config, "parse_config(BAD PATH) returns undef config");
	ok(!$checks, "parse_checks(BAD PATH) returns undef checks");
}

###################################################################

{ # Check configuration
	my $now = time;
	my ($config, $checks) = NLMA::parse_config('t/data/config/check-config.yml');

	is($config->{timeout},  33, "Default timeout is 33s");
	is($config->{interval}, 44, "Default interval is 44s");

	is(@$checks, 3, "Retrieved 3 checks from configuration");
	cmp_deeply([
			$checks->[0]{name},
			$checks->[1]{name},
			$checks->[2]{name},
		], [qw(check1 second_check check3)],
		"Ordered Checks");

	my $check;

	$check = $checks->[0];
	is($check->{name}, "check1", "<name> set properly");
	is($check->{timeout}, $config->{timeout}, "<timeout> default");
	is($check->{on_timeout}, $config->{on_timeout}, "<on_timeout> default");
	is($check->{interval}, $config->{interval}, "<interval> default");
	is($check->{attempts}, 1, "<attempts> default");
	is($check->{retry}, 60, "<retry> default");
	is($check->{environment}, "default", "<environment> default");

	is($check->{started_at}, 0, "<started_at> is initially 0");
	is($check->{duration},   0, "<duration> is initially 0");
	is($check->{ended_at},   0, "<ended_at> is initially 0");
	is($check->{current},    0, "<current> attempt is initially 0");

	is($check->{is_soft_state}, 0, "<is_soft_state> is initially 0");
	is($check->{last_state},    0, "<last_state> is initially 0");
	is($check->{state},         0, "<state> is initially 0");

	is($check->{pid},         -1, "<pid> is initially -1 (invalid value)");
	is($check->{exit_status}, -1, "<exit_status> is initially -1 (invalid value)");

	is($check->{output}, "", "<output> is initially blank");

	cmp_ok($check->{next_run}, '>=', $now, "<next_run> is now or in the future");

	# Test that we overrode specific values for check2
	$check = $checks->[1];
	is($check->{name}, "second_check", "<name> overridden for check2");
	is($check->{interval}, 20, "<interval> overridden for check2");
	is($check->{timeout},   6, "<timeout> overridden for check2");
	is($check->{attempts},  4, "<attempts> overridden for check2");
	is($check->{retry},    11, "<retry> overridden for check2");
	is($check->{environment}, "dev", "<environment> overridden for check2");
}

{ # Check Splay
	my ($config, $checks) = NLMA::parse_config('t/data/config/check-splay.yml');

	is($config->{startup_splay}, 10, "Startup splay is 10 seconds");

	is(@$checks, 4, "Retrieved 4 checks from configuration");
	cmp_deeply([
			$checks->[0]{name},
			$checks->[1]{name},
			$checks->[2]{name},
			$checks->[3]{name},
		], [qw(check_raid check_mem check_disk check_cpu)],
		"Ordered Checks");

	my $start = $checks->[0]{next_run};
	cmp_ok($start, '>', time - 10, "First check scheduled to be run soon");
}

{ # Include files
	my ($config, $checks) = NLMA::parse_config('t/data/config/includes.yml');

	cmp_set([map { $_->{name} } @$checks],
		[qw[cpu load disks database iowait apache]],
		"Found all 6 checks");

	cmp_set($config->{errors},   [], 'No errors on includes test');
	cmp_set($config->{warnings}, [], 'No warnings on includes test');
}

{ # Including files that do not exist

	my ($config, $checks) = NLMA::parse_config('t/data/config/bad-includes.yml');
	cmp_set([map { $_->{name} } @$checks],
		[qw[cpu load disks]],
		"Found all 3 baseline checks");

	cmp_set($config->{errors}, [
			q(Failed to read inc/DOES-NOT-EXIST.yml),
			q(Failed to read inc/web),
			q(Failed to read /etc/no/such/file.yml),
			q(Failed to parse inc/notyaml.png),
			q(Failed to parse inc/corrupt.yml),
			q(Failed to parse /etc/passwd), # this is the absolute file test;
			                                # /etc/passwd should exist globally.
		], 'Bad file includes trigger criticals');
	cmp_set($config->{warnings}, [], 'No warnings on bad includes');
}

{ # Including files that override other checks
	my ($config, $checks) = NLMA::parse_config('t/data/config/includes-override.yml');

	cmp_set([map { $_->{name} } @$checks],
		[qw[cpu load disks newcheck]],
		"Found 4 checks");

	# Find the index of the 'cpu' check;
	my $i;
	for ($i = 0; $i < @$checks; $i++) {
		last if $checks->[$i]{name} eq 'cpu';
	}
	ok(exists $checks->[$i], "Found cpu check");
	is($checks->[$i]{command}, 'dummy', "cpu check command was not overridden");

	cmp_set($config->{errors}, [], 'No errors on check redefinition');
	cmp_set($config->{warnings}, [
			q(Attempted to redefine 'cpu' check in inc/override.yml)
		], "Check redefinition triggers warnings");
}

{ # Parsing a bad config should return (undef,undef)
	my ($config, $checks) = NLMA::parse_config('t/data/config/bad.yml');

	ok(!defined($config), "config result not defined for bad YAML");
	ok(!defined($checks), "checks result not defined for bad YAML");

	($config, $checks) = NLMA::parse_config('t/data/config/bad-whitespace.yml');
	ok(!defined($config), "config result not defined for bad whitespace");
	ok(!defined($checks), "checks result not defined for bad whitespace");

	($config, $checks) = NLMA::parse_config('t/data/config/bad-missing-command.yml');
	ok(!defined($config), "config result not defined for missing command");
	ok(!defined($checks), "checks result not defined for missing command");
}

subtest "merging global + check env variables" => sub {
	my ($config, $checks) = Nagios::Agent::parse_config('t/data/config/env_merging.yml');

	cmp_deeply $config, superhashof({
			env => { env_test1 => 'true', env_test2 => 'false' },
		}), "config result contains top level env hash for global envrionment settings";

	cmp_deeply $checks, bag(
		superhashof({ # check1 tests pulling defaults into a check without an env
			name => 'check1',
			env => {
				env_test1 => 'true',
				env_test2 => 'false',
				MONITOR_FEEDER_TARGETS => 'df01.example.com,df02.example.com',
			}
		}),
		superhashof({ # check2 tests merging defaults with check-specific env
			name => 'check2',
			env => {
				env_test1 => 'true',
				env_test2 => 'false',
				local_env => 'truish',
				MONITOR_FEEDER_TARGETS => 'df01.example.com,df02.example.com',
			}
		}),
		superhashof({ # check3 tests overwiting a default with a check-specific env
			name => 'check3',
			env => {
				env_test1 => 'false',
				env_test2 => 'false',
				MONITOR_FEEDER_TARGETS => 'df01.example.com,df02.example.com',
			}
		}),
	), "check definitions have env variables merged correctly" or diag explain $checks;
};


done_testing;
