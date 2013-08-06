use strict;
use warnings;
use ExtUtils::MakeMaker;

WriteMakefile(
	NAME                => 'Nagios::Agent',
	AUTHOR              => q{James Hunt <jhunt@synacor.com>},
	VERSION_FROM        => 'lib/Nagios/Agent.pm',
	ABSTRACT_FROM       => 'lib/Nagios/Agent.pm',
	($ExtUtils::MakeMaker::VERSION >= 6.3002
		? ('LICENSE'=> 'perl')
		: ()),
	PL_FILES            => {},
	EXE_FILES           => [qw(
			bin/alert
			bin/nlma
			bin/nlma-debug
			bin/nlma-timeout
		)],
	PREREQ_PM => {
		'Test::More' => 0,
	},
	dist                => { COMPRESS => 'gzip -9f', SUFFIX => 'gz', },
	clean               => { FILES => 'Nagios-Agent-*' },
);
