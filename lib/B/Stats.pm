package B::Stats;
our $VERSION = '0.01_20111206';

=head1 NAME

B::Stats - print optree statistics

=head1 SYNOPSIS

  perl -MB::Stats myprog.pl # all
  perl -MO=Stats myprog.pl  # compile-time only
  perl -MB::Stats[,OPTIONS] myprog.pl

=head1 DESCRIPTION

Print statistics for all generated ops.

static analysis at compile-time,
static analysis at end-time to include all runtime added modules,
and dynamic analysis at run-time, as with a profiler.

The purpose is to help you in your goal:

    no bloat;

=head1 OPTIONS

=over

=item -c I<static>

Do static analysis at compile-time. This does not include all run-time require packages.
Invocation via -MO=Stats does this automatically.

=item -e I<end>

Do static analysis at end-time. This is includes all run-time require packages.
This calculates the heap space for the optree.

=item -r I<run>

Do dynamic run-time analysis of all actually visited ops, similar to a profiler.
Single ops can be called multiple times.

=item -a I<all (default)>

Same as -c,-e,-r: static compile-time, end-time and dynamic run-time.

=item -t I<table>

Tabular list of -c, -e and -r results.

=item -u I<summary>

Short summary only, no op class.
With -t only the final table(s).

=item -F I<Files>

Prints included file names

=item -x I<fragmentation>  B<NOT YET>

Calculates the optree I<fragmentation>. 0.0 is perfect, 1.0 is very bad.

A perfect optree has no null ops and every op->next is immediately next
to the op.

=item -f<op,...> I<filter>  B<NOT YET>

Filter for op names and classes. Only calculate the given ops, resp. op class.

  perl -MB::Stats,-fLOGOP,COP,concat myprog.pl

=item -lF<logfile> B<NOT YET>

Print output only to this file. Default: STDERR

=back

=head1 METHODS

=over

=cut

use strict;
# B includes 14 files and 3821 lines. TODO: add it to our XS
use B ();
# XSLoader adds 0 files and 0 lines, already with B
use XSLoader ();
# Opcodes-0.10 adds 6 files and 5303-3821 lines: Carp, AutoLoader, subs
# Opcodes-0.11 adds 2 files and 4141-3821 lines: subs
# use Opcodes; # deferred to run-time below
our ($static, @runtime, $compiled);
my (%opt, $nops, $rops, @all_subs, $frag, %roots);
my ($c_count, $e_count, $r_count);

# check options
sub import {
  $DB::single = 1 if defined &DB::deep;
#print STDERR "opt: ",join(',',@_),"; "; # for Debugging
  for (@_) { # switch bundling without Getopt bloat
    if (/^-?([acerxtFu])(.*)$/) {
      $opt{$1} = 1;
      my $rest = $2;
      do {
	if ($rest =~ /^-?([acerxtFu])(.*)$/) {
	  $opt{$1} = 1;
	  $rest = $2;
	}
      } while $rest;
    }
  }
  # -ffilter and -llog not yet
  $opt{a} = 1 if !$opt{c} and !$opt{e} and !$opt{r}; # default
  $opt{c} = $opt{e} = $opt{r} = 1 if $opt{a};
#warn "%opt: ",keys %opt,"\n"; # for Debugging
}

sub _class {
    my $name = ref shift;
    $name =~ s/^.*:://;
    return $name;
}

# static
sub _count_op {
  my $op = shift;
  $nops++; # count also null ops
  if ($$op) {
    $static->{name}->{$op->name}++;
    $static->{class}->{_class($op)}++;
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
      for grep { _class($_) eq "CV" } $cv->PADLIST->ARRAY->ARRAY;
  }
  return unless ${$cv->START} and ${$cv->ROOT};
  # $starts{$name} = $cv->START;
  $roots{$name} = $cv->ROOT;
};
sub B::SPECIAL::_mypush_starts{}

sub _walkops {
  my ($callback, $data) = @_;
  %roots  = ( '__MAIN__' =>  B::main_root()  );
  B::walksymtable(\%main::,
	       '_mypush_starts',
	       sub {
		 return if scalar grep {$_[0] eq $_."::"} ('B::Stats');
		 1;
	       }, # Do not eat our own children!
	       '');
  push @all_subs, { root => $_->ROOT, start => $_->START}
    for grep { _class($_) eq "CV" } B::main_cv->PADLIST->ARRAY->ARRAY;
  for $sub (keys %roots) {
    _walkoptree_simple($roots{$sub}, $callback, $data);
  }
  $sub = "__ANON__";
  for (@all_subs) {
    _walkoptree_simple($_->{root}, $callback, $data);
  }
}

sub _walkoptree_simple {
  my ($op, $callback, $data) = @_;
  $callback->($op,$data);
  if ($$op && ($op->flags & B::OPf_KIDS)) {
    my $kid;
    for ($kid = $op->first; $$kid; $kid = $kid->sibling) {
      _walkoptree_simple($kid, $callback, $data);
    }
  }
}

=item compile

Static -c check at CHECK time. Triggered by -MO=Stats,-OPTS

=cut

sub compile {
  import(@_); # check options via O
  $compiled++;
  $opt{c} = 1;
  return sub {
    $nops = 0;
    _walkops(\&_count_op);
    output($static, $nops, 'static compile-time');
  }
}

=item rcount (opcode)

Returns run-time count per op type.

=item output ($count-hash, $ops, $name)

General formatter

=cut

sub output {
  my ($count, $ops, $name) = @_;

  my $files = scalar keys %INC;
  my $lines = 0;
  for (values %INC) {
    print STDERR $_,"\n" if $opt{F};
    open IN, "<", "$_";
    # Todo: skip pod?
    while (<IN>) { chomp; s/#.*//; next if not length $_; $lines++; };
    close IN;
  }
  print STDERR "\nB::Stats $name:\nfiles=$files\tlines=$lines\tops=$ops\n";
  return if $opt{t} and $opt{u};

  print STDERR "\nop name:\n";
  for (sort { $count->{name}->{$b} <=> $count->{name}->{$a} }
       keys %{$count->{name}}) {
    my $l = length $_;
    print STDERR $_, " " x (10-$l), "\t", $count->{name}->{$_}, "\n";
  }
  unless ($opt{u}) {
    print STDERR "\nop class:\n";
    for (sort { $count->{class}->{$b} <=> $count->{class}->{$a} }
	 keys %{$count->{class}}) {
      my $l = length $_;
      print STDERR $_, " " x (10-$l), "\t", $count->{class}->{$_}, "\n";
    }
  }
}

=item output_runtime

-r formatter.

Prepares count hash from the runtime generated structure in XS and calls output().

=cut

sub output_runtime {
  $r_count = {};
  require Opcodes;
  my $maxo = Opcodes::opcodes();
  # @optype only since 5.8.9 in B
  my @optype = qw(OP UNOP BINOP LOGOP LISTOP PMOP SVOP PADOP PVOP LOOP COP);
  for my $i (0..$maxo-1) {
    if (my $count = rcount($i)) {
      my $name = Opcodes::opname($i);
      if ($name) {
	my $class = $optype[ Opcodes::opclass($i) ];
	$r_count->{name}->{ $name } += $count;
	$r_count->{class}->{ $class } += $count;
	$rops += $count;
      } else {
	warn "invalid name for opcount[$i]";
      }
    }
  }
  # XXX substract 11 for nextstate, 9 for padsv non-threaded
  output($r_count, $rops, 'dynamic run-time');
}

=item output_table

-t formatter

=cut

sub output_table {
  my ($c, $e, $r) = @_;
  format STDERR_TOP =

B::Stats table:
@<<<<<<<<<<	@>>>>	@>>>>	@>>>>
"",             "-c",   "-e",   "-r"
.
  write STDERR;
  format STDERR =
@<<<<<<<<<<	@>>>>	@>>>>	@>>>>
$_,$c_count->{name}->{$_},$e_count->{name}->{$_},$r_count->{name}->{$_}
.
  if (%$e_count) {
    for (sort { $e_count->{name}->{$b} <=> $e_count->{name}->{$a} }
         keys %{$e_count->{name}}) {
      write STDERR;
    }
  } else {
    for (sort { $c_count->{name}->{$b} <=> $c_count->{name}->{$a} }
         keys %{$c_count->{name}}) {
      write STDERR;
    }
  }
}

=back

=cut

# Called not via -MO=Stats, rather -MB::Stats
CHECK {
  compile->() if !$compiled and $opt{c};
}

END {
  $c_count = $static;
  if ($opt{e}) {
    $nops = 0;
    $static = {};
    _walkops(\&_count_op);
    output($static, $nops, 'static end-time');
    $e_count = $static;
  }
  output_runtime() if $opt{r};
  output_table($c_count, $e_count, $r_count) if $opt{t};
}

XSLoader::load 'B::Stats', $VERSION;
1;
