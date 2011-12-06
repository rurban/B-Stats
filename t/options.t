#!perl

use Test::More tests => 15;

my $X = $^X =~ m/\s/ ? qq{"$^X"} : $^X;
# fake home for cpan-testers
# no fake requested ## local $ENV{HOME} = tempdir( CLEANUP => 1 );
my $redir = $^O eq 'MSWin32' ? '' : '2>&1';

# normal
my $c = qx{ $X -Mblib -MB::Stats=-c,-u t/test.pl $redir };
like( $c, qr/^B::Stats static compile-time:/m, "-MB::Stats=-c,-u => c" );
unlike( $c, qr/^B::Stats static end-time:/m,   "-MB::Stats=-c,-u => !e" );
unlike( $c, qr/^B::Stats dynamic run-time:/m,  "-MB::Stats=-c,-u => !r" );
unlike(   $c, qr/^op class:/m,                 "-MB::Stats,-c,-u => u" );

like( $c, qr/^nextstate\s+[1-9]\d+$/m, "nextstate > 0" );

$c = qx{ $X -Mblib -MB::Stats=-r,-u t/test.pl $redir };
unlike( $c, qr/^B::Stats static compile-time:/m, "-MB::Stats=-c,-u => !c" );
unlike( $c, qr/^B::Stats static end-time:/m,   "-MB::Stats=-c,-u => !e" );
like( $c, qr/^B::Stats dynamic run-time:/m,    "-MB::Stats -r" );

# O:
$c = qx{ $X -Mblib -MO=Stats,-c,-u t/test.pl $redir };
like( $c, qr/^B::Stats static compile-time:/m, "-MO=Stats,-c,-u => c" );
unlike( $c, qr/^B::Stats static end-time:/m,   "-MO=Stats,-c,-u => !e" );
unlike( $c, qr/^B::Stats dynamic run-time:/m,  "-MO=Stats,-c,-u => !r" );

# switch bundling
$c = qx{ $X -Mblib -MB::Stats=-ceu t/test.pl $redir };
like( $c, qr/^B::Stats static compile-time:/m, "-MO=Stats,-ceu => c" );
like( $c, qr/^B::Stats static end-time:/m,     "-MO=Stats,-ceu => e" );
TODO: {
  local $TODO = "switch bundling not yet";
  unlike( $c, qr/^op class:/m,                   "-MO=Stats,-ceu => u" );
  unlike( $c, qr/^B::Stats dynamic run-time:/m,  "-MO=Stats,-ceu => !r" );
}

