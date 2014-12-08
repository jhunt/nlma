#!perl

use Test::More;
use NLMA;

{ # dumb helper functions

	is(NLMA::MAX(1,2), 2, "MAX works on positive integers");
	is(NLMA::MAX(2,1), 2, "MAX works on positive integers");

	is(NLMA::MIN(1,2), 1, "MIN works on positive integers");
	is(NLMA::MIN(2,1), 1, "MIN works on positive integers");

	is(NLMA::MAX(-4,-10), -4, "MAX works on negative integers");
	is(NLMA::MAX(-10,-4), -4, "MAX works on negative integers");

	is(NLMA::MIN(-4,-10), -10, "MIN works on negative integers");
	is(NLMA::MIN(-10,-4), -10, "MIN works on negative integers");

	is(NLMA::MAX(-2, 2), 2, "MAX works on positive/negative integers");
	is(NLMA::MAX(2, -2), 2, "MAX works on positive/negative integers");

	is(NLMA::MIN(-2, 2), -2, "MIN works on positive/negative integers");
	is(NLMA::MIN(2, -2), -2, "MIN works on positive/negative integers");
}

done_testing;
