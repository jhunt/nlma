use strict;
use warnings;
use ExtUtils::MakeMaker;

WriteMakefile(
	NAME                => 'NLMA',
	AUTHOR              => q{James Hunt <jhunt@synacor.com>},
	VERSION_FROM        => 'lib/NLMA.pm',
	ABSTRACT_FROM       => 'lib/NLMA.pm',
	($ExtUtils::MakeMaker::VERSION >= 6.3002
		? ('LICENSE'=> 'gpl_3')
		: ()),
	PL_FILES            => {},
	EXE_FILES           => [qw(
			bin/alert
			bin/nlma
			bin/nlma-debug
			bin/nlma-config
			bin/nlma-timeout
		)],
	PREREQ_PM => {
		'Test::More' => 0,
	},
	dist                => { COMPRESS => 'gzip -9f', SUFFIX => 'gz', },
	clean               => { FILES => 'NLMA-*' },
);
