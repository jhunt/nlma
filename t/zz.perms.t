#!perl

use Test::More;
do "t/common.pl";

plan skip_all => "Skipping final chown (not running as root)" unless $> == 0;
plan tests => 1;

my @stat = stat 't/zz.perms.t';
qx{chown -R $stat[4]:$stat[5] cover_db t/tmp blib pm_to_blib};
ok(1);
