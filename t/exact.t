#!perl

use Test::More;
Test::More->import('no_plan') if $] > 5.008005;
plan skip_all => 'done_testing requires 5.8.6' if $] <= 5.008005;

my $X = $^X =~ m/\s/ ? qq{"$^X"} : $^X;
# no fake requested ## local $ENV{HOME} = tempdir( CLEANUP => 1 );
my $redir = $^O eq 'MSWin32' ? '' : '2>&1';

diag "compare B::Terse with B::Stats";
my $t = `$X -Mblib -MO=-qq,Terse -e"print 1 for (1..3)" | $X -anl -e"print \$F[2]"`;
my $c = `$X -Mblib -MO=-qq,Stats,-u -e"print 1 for (1..3)" $redir`;
my (%t, %c, $ok);
my @lines = split(/\n/,$t);
my $ops = scalar(@lines);
$t{$_}++ for @lines;

TODO: {
  local $TODO = "B::Stats still not exact, pollutes the result";
  my ($files) = $c =~ /^files=(\d+)\s/m;
  is ($files, 1, "files=1");
  my ($lines) = $c =~ /\slines=(\d+)\s/m;
  is ($lines, 1, "files=1");
  my ($cops) = $c =~ /\sops=(\d+)\s/m;
  is ($cops, $ops, "ops=$ops");

  for (keys %t) {
    my ($s) = $c =~ /^$_\s+(\d+)/m;
    is ($s, $t{$_}, "$_ = $t{$_}");
  }
}

Test::More::done_testing() if defined &Test::More::done_testing and $] <= 5.008005;
