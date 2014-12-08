#!perl -T

use Test::More tests => 1;

BEGIN {
    use_ok( 'NLMA' );
}

diag( "Testing NLMA $NLMA::VERSION, Perl $], $^X" );
