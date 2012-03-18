use strict;
use warnings;
use ExtUtils::MakeMaker;

WriteMakefile(
    NAME                => 'Nagios::Poller',
    AUTHOR              => q{James Hunt <jhunt@synacor.com>},
    VERSION_FROM        => 'lib/Nagios/Poller.pm',
    ABSTRACT_FROM       => 'lib/Nagios/Poller.pm',
    ($ExtUtils::MakeMaker::VERSION >= 6.3002
      ? ('LICENSE'=> 'perl')
      : ()),
    PL_FILES            => {},
    PREREQ_PM => {
        'Test::More' => 0,
    },
    dist                => { COMPRESS => 'gzip -9f', SUFFIX => 'gz', },
    clean               => { FILES => 'Nagios-Poller-*' },
);
