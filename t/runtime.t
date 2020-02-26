#!perl

use Test::More tests => 6;

my $X = $^X =~ m/\s/ ? qq{"$^X"} : $^X;
# fake home for cpan-testers
# no fake requested ## local $ENV{HOME} = tempdir( CLEANUP => 1 );
my $redir = '2>&1';

$c = qx{ $X -Iblib/arch -Iblib/lib -MB::Stats=-r t/test.pl $redir };
unlike( $c, qr/^B::Stats static compile-time:/m, "-MB::Stats=-r => !c" );
unlike( $c, qr/^B::Stats static end-time:/m,     "-MB::Stats=-r => !e" );
like( $c, qr/^B::Stats dynamic run-time:/m,  "-MB::Stats=-r => r" );
like( $c, qr/^op class:/m,                   "-MB::Stats,-r => !u" );
like( $c, qr/^nextstate\s+[1-9]\d*$/m, "nextstate > 0" );
TODO: {
    local $TODO = '5.31.9 END limitation' if $] >= 5.031009;
    like( $c, qr/^COP\s+[1-9]\d*$/m, "COP > 0" );
}
