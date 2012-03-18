#!perl -T

use Test::More tests => 1;

BEGIN {
    use_ok( 'Nagios::Poller' );
}

diag( "Testing Nagios::Poller $Nagios::Poller::VERSION, Perl $], $^X" );
