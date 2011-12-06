package B::Stats;
our $VERSION = '0.01_20111205';

=head1 NAME

B::Stats - optree statistics

=head1 SYNOPSIS

  perl -MB::Stats myprog.pl # all
  perl -MO=Stats myprog.pl  # compile-time only
  perl -MB::Stats[,OPTIONS] myprog.pl

=head1 DESCRIPTION

Print statistics for all generated ops.

static analysis at compile-time,
static analysis at end-time to include all runtime added modules,
and dynamic analysis at run-time.

=head1 OPTIONS

=over

=item -c I<static>

Do static analysis at compile-time. This does not include all run-time require packages.
Invocation via -MO=Stats does this.

=item -e I<end>

Do static analysis at end-time. This is includes all run-time require packages.
This calculates the heap space for the optree.

=item -r I<run>

Do dynamic run-time analysis of all actually visited ops, similar to a profiler.

=item -a I<all (default)>

-cer: static compile-time and end-time and dynamic run-time.

=item -u I<summary>

Short summary only, no details per op.

=item -lF<logfile>

Print output only to this file. Default: STDERR

=item -f I<fragmentation>

Calculates the optree I<fragmentation>. 0.0 is perfect, 1.0 is very bad.

A perfect optree has no null ops and every op->next is immediately next
to the op.

=item -f<op,...> I<filter>

Filter for op names and classes. Only calculate the given ops, resp. op class.

  perl -MB::Stats,-fLOGOP,COP,concat myprog.pl

=back

=cut

use B qw(main_root class OPf_KIDS walksymtable);
use XSLoader;
use Opcodes;
our ($static, @runtime, $compiled, @bad_stashes);
my (%opt, $nops, $rops, @all_subs, $frag);
BEGIN {
  @runtime = ();
  @bad_stashes = ('B::Stats');
  $opt{c} = $opt{e} = 1;
  # $opt{u} = 1; # TODO opts
  # $opt{r} = 1; # run-time XS TODO
}

# static
sub count_op {
  my $op = shift;
  $nops++; # count also null ops
  if ($$op) {
    $static->{name}->{$op->name}++;
    $static->{class}->{class($op)}++;
  }
}

# from B::Utils
our $sub;

sub B::GV::_mypush_starts {
  my $name = $_[0]->STASH->NAME."::".$_[0]->SAFENAME;
  return unless ${$_[0]->CV};
  my $cv = $_[0]->CV;
  if ($cv->PADLIST->can("ARRAY")
      and $cv->PADLIST->ARRAY
      and $cv->PADLIST->ARRAY->can("ARRAY"))
  {
    push @all_subs, { root => $_->ROOT, start => $_->START}
      for grep { class($_) eq "CV" } $cv->PADLIST->ARRAY->ARRAY;
  }
  return unless ${$cv->START} and ${$cv->ROOT};
  $starts{$name} = $cv->START;
  $roots{$name} = $cv->ROOT;
};
sub B::SPECIAL::_mypush_starts{}

sub walkops {
  my ($callback, $data) = @_;
  my %roots  = ( '__MAIN__' =>  main_root()  );
  walksymtable(\%main::,
	       '_mypush_starts',
	       sub {
		 return if scalar grep {$_[0] eq $_."::"} @bad_stashes;
		 1;
	       }, # Do not eat our own children!
	       '');
  push @all_subs, { root => $_->ROOT, start => $_->START}
    for grep { class($_) eq "CV" } B::main_cv->PADLIST->ARRAY->ARRAY;
  for $sub (keys %roots) {
    walkoptree_simple($roots{$sub}, $callback, $data);
  }
  $sub = "__ANON__";
  for (@all_subs) {
    walkoptree_simple($_->{root}, $callback, $data);
  }
}

sub walkoptree_simple {
  my ($op, $callback, $data) = @_;
  $callback->($op,$data);
  if ($$op && ($op->flags & OPf_KIDS)) {
    my $kid;
    for ($kid = $op->first; $$kid; $kid = $kid->sibling) {
      walkoptree_simple($kid, $callback, $data);
    }
  }
}

# static at CHECK time. triggered by -MO=Stats
sub compile {
  $DB::single = 1 if defined &DB::deep;
  $compiled++;
  return sub {
    $nops = 0;
    walkops(\&count_op);
    output($static, $nops, 'static compile-time');
  }
}

sub output_runtime {
  my $rt = {};
  my $i = 0;
  for (@runtime) {
    if (my $count = $_->[0]) {
      $rt->{name}->{ opcode($i) } += $count;
      $rt->{class}->{ opclass($i) } += $count;
      $rops += $count;
    }
    $i++;
  }
  output($rt, $rops, 'dynamic run-time');
}

sub output {
  my ($count, $ops, $name) = @_;

  my $files = scalar keys %INC;
  my $lines = 0;
  for (values %INC) {
    open IN, "<", "$_";
    # Todo: skip pod?
    while (<IN>) { chomp; s/#.*//; next if not length $_; $lines++; };
    close IN;
  }
  print STDERR "\nB::Stats $name:\nfiles=$files\tlines=$lines\tops=$ops\n";
  print STDERR "\nop name:\n";
  for (sort { $count->{name}->{$b} <=> $count->{name}->{$a} } keys %{$count->{name}}) {
    my $l = length $_;
    print STDERR $_, " " x (10-$l), "\t", $count->{name}->{$_}, "\n";
  }

  unless ($opt{u}) {
    print STDERR "\nop class:\n";
    for (sort { $count->{class}->{$b} <=> $count->{class}->{$a} } keys %{$count->{class}}) {
      my $l = length $_;
      print STDERR $_, " " x (10-$l), "\t", $count->{class}->{$_}, "\n";
    }
  }
}

# not via -MO=Stats, rather -MB::Stats
CHECK {
  compile->() if $opt{r} and !$compiled;
}

END {
  if ($opt{e}) {
    $nops = 0;
    $static = {};
    walkops(\&count_op);
    output($static, $nops, 'static end-time');
  }
  output_runtime() if $opt{r};
}

# still fails
# XSLoader::load 'B::Stats', $VERSION;

1;
