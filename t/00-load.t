#!perl -T

use Test::More tests => 1;

BEGIN {
    use_ok( 'Nagios::Agent' );
}

diag( "Testing Nagios::Agent $Nagios::Agent::VERSION, Perl $], $^X" );
