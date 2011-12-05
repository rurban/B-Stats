package B::Stats;
our $VERSION = '0.01_20111205';

=head1 NAME

B::Stats - optree statistics

=head1 SYNOPSIS

  perl -MB::Stats myprog.pl
  perl -MO=Stats myprog.pl
  perl -MO=Stats[,OPTIONS] myprog.pl

=head1 DESCRIPTION

Print statistics for all generated ops.

static analysis at compile-time,
static analysis at end-time to include all runtime added modules,
and dynamic analysis at run-time.

=head1 OPTIONS

=over

=item -llogfile

Print output only to this file. Default: STDERR

=item -s I<static>

Only do static analysis at compile-time. This does not include all run-time require packages.

=item -e I<end>

Only do static analysis at end-time. This is includes all run-time require packages.
This calculates the heap space for the optree.

=item -r I<run>

Only do dynamic run-time analysis of all actually visited ops, similar to a profiler.

=item -a I<all (default)>

-ser: static compile-time and end-time and dynamic run-time.

=item -f I<fragmentation>

Calculates the optree I<fragmentation>. 0.0 is perfect, 1.0 is very bad.

=item -u I<summary>

Short summary only, no details per op.

=item -f<op,...> I<filter>

Filter for ops and opclasses. Only calculate the given ops, resp. op class.

  perl -MO=Stats,-fLOGOP,COP,concat myprog.pl

=back

=cut

use B qw(main_root class OPf_KIDS walksymtable);
our ($count);
my (%opt, $files, $lines, $ops, $compiled, @anon_subs);

# $opt{u} = 1; # TODO opts

sub count_op {
  my $op = shift;
  $ops++; # count also null ops
  if ($$op) {
    $count->{name}->{$op->name}++;
    $count->{class}->{class($op)}++;
  }
}

# from B::Utils
our ($file, $line);
our $sub;

sub B::GV::_mypush_starts {
  my $name = $_[0]->STASH->NAME."::".$_[0]->SAFENAME;
  return unless ${$_[0]->CV};
  my $cv = $_[0]->CV;
  if ($cv->PADLIST->can("ARRAY")
      and $cv->PADLIST->ARRAY
      and $cv->PADLIST->ARRAY->can("ARRAY"))
  {
    push @anon_subs, { root => $_->ROOT, start => $_->START}
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
  push @anon_subs, { root => $_->ROOT, start => $_->START}
    for grep { class($_) eq "CV" } B::main_cv->PADLIST->ARRAY->ARRAY;
  for $sub (keys %roots) {
    walkoptree_simple($roots{$sub}, $callback, $data);
  }
  $sub = "__ANON__";
  for (@anon_subs) {
    walkoptree_simple($_->{root}, $callback, $data);
  }
}

sub walkoptree_simple {
  my ($op, $callback, $data) = @_;
  #do_stat($op);
  #($file, $line) = ($op->file, $op->line) if $op->isa("B::COP");
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
  $DB::single=1 if defined &DB::DB;
  $compiled++;
  return sub {
    $ops = 0;
    walkops(\&count_op);
    output($ops, 'static compile-time');
  }
}

sub output {
  my $ops = shift;
  my $name = shift;

  my $files = scalar keys %INC;
  my $lines = 0;
  for (values %INC) {
    open IN, "<", "$_";
    # Todo: skip pod
    while (<IN>) { chomp; s/#.*//; next if not length $_; $lines++; };
    close IN;
  }
  print "B::Stats $name:\nfiles=$files\tlines=$lines\tops=$ops\n";
  print "\nop name:\n";
  for (sort { $count->{name}->{$b} <=> $count->{name}->{$a} } keys %{$count->{name}}) {
    my $l = length $_;
    print STDERR $_, " " x (10-$l), "\t", $count->{name}->{$_}, "\n";
  }

  unless ($opt{u}) {
    print "\nop class:\n";
    for (sort { $count->{class}->{$b} <=> $count->{class}->{$a} } keys %{$count->{class}}) {
      my $l = length $_;
      print STDERR $_, " " x (10-$l), "\t", $count->{class}->{$_}, "\n";
    }
  }
}

# not via -MO=Stats, rather -MB::Stats
CHECK {
  compile unless $compiled;
}

END {
  $ops = 0;
  walkops(\&count_op);
  output($ops, 'static end-time');
  
  # output($ops, 'dynamic run-time');
}

1;
