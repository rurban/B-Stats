#!perl

use Test::More;

my $X = $^X =~ m/\s/ ? qq{"$^X"} : $^X;
# no fake requested ## local $ENV{HOME} = tempdir( CLEANUP => 1 );
my $redir = $^O eq 'MSWin32' ? '' : '2>&1';

diag "compare B::Terse with B::Stats";
my $t = `$X -Mblib -MO=-qq,Terse -e"print 1 for (1..3)" | $X -anl -e'print \$F[2]'`;
my $c = `$X -Mblib -MO=-qq,Stats,-u -e'print 1 for (1..3)' $redir`;
my (%t, %c, $ok);
my $ops = scalar split(/\n/,$t);
$t{$_}++ for split/\n/,$t;

TODO: {
  local $TODO = "B::Stats still pollutes the result";
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

done_testing;
