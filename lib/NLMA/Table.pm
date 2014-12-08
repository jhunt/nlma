package NLMA::Table;

use strict;
use warnings;

my %COLORS = qw(
	black   0;30
	red     0;31   bright_red     1;31
	green   0;32   bright_green   1;32
	yellow  0;33   bright_yellow  1;33
	blue    0;34   bright_blue    1;34
	magenta 0;35   bright_magenta 1;35
	cyan    0;36   bright_cyan    1;36
	white   0;37   bright_white   1;37
);

sub _color
{
	my ($name) = @_;
	return '' unless $name;
	return "\e[0m" if $name eq 'clear';
	return '' unless exists $COLORS{$name};
	return "\e[$COLORS{$name}m";
}

sub new
{
	my ($class, $columns) = @_;
	bless {
		cols => $columns,
		widths => {map { $_ => length $_; } @$columns},
		rows => [],
	}, $class;
}

sub append
{
	my ($self, $row, $color) = @_;
	push @{$self->{rows}}, [$row, $color];
	for my $k (keys %$row) {
		my $a = $self->{widths}->{$k} || 0;
		my $b = length $row->{$k};

		$self->{widths}->{$k} = ($a > $b ? $a : $b);
	}
}

sub sort
{
	my ($self, $sub) = @_;
	my @tmp = sort { $sub->($a->[0], $b->[0]); } @{$self->{rows}};
	$self->{rows} = \@tmp;
}

sub _pad
{
	my ($str, $len) = @_;
	$len = ($len || 0) - length $str;
	$len = 0 if $len < 0;
	$str . (" " x $len);
}

sub empty
{
	my ($self) = @_;
	@{$self->{rows}} == 0;
}

sub print_row
{
	my ($self, $row, $color) = @_;

	print _color($color);
	for my $col (@{$self->{cols}}) {
		if (!exists $row->{$col}) {
			print _pad("~", 1);
		} else {
			print _pad($row->{$col}, $self->{widths}->{$col});
		}
		print "  ";
	}

	if ($color) {
		print _color('clear');
	}
	print "\n";
}

sub print
{
	my ($self) = @_;
	return if $self->empty;

	for my $col (@{$self->{cols}}) {
		my $header = uc $col;
		print _pad($header, $self->{widths}->{$col}), "  ";
	}
	print "\n";
	for my $row (@{$self->{rows}}) {
		$self->print_row(@$row);
	}
}

sub dump_row
{
	my ($self, $row) = @_;
	my @tokens = ();
	for my $col (@{$self->{cols}}) {
		push @tokens, $row->{$col};
	}
	print join("|", @tokens), "\n";
}

sub dump
{
	my ($self) = @_;
	for my $row (@{$self->{rows}}) {
		$self->dump_row(@$row);
	}
}

1;

=head1 NAME

NLMA::Table

=head1 FUNCTIONS

=over

=item dump

=item dump_row

=item print

=item print_row

=item empty

=item _pad

=item sort

=item append

=item new

=cut
