#!perl

use Test::More;
use NLMA;
use YAML::XS;

{ # basic dump to writable location
	qx(mkdir -p t/tmp);
	my ($config, $checks) = NLMA::parse_config("t/data/config/dump.yml");

	qx(rm -f t/tmp/nlma.*.yml);
	NLMA::dump_config($config, $checks);
	my $file = qx(ls t/tmp/nlma.*.yml); chomp $file;
	isnt($file, "", 'dump_config created a file');
	ok(-f $file, "dump_config created a real file");

	open my $fh, '<', $file or BAIL_OUT("could not open dump file ($file) for reading / verification: $!");

	my $yaml = do { local $/ = undef; <$fh> };
	isnt($yaml, '', "YAML dumped");

	my ($config2, $checks2) = Load($yaml);
	close $fh;
	ok($config2, "Retrieved global configuration section from dump file");
	ok($checks2, "Retrieved check definitions section from dump file");
}

done_testing;
