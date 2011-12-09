package B::Stats;
our $VERSION = '0.02';

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

our (%B_inc, %B_env);
BEGIN { %B_inc = %INC; }

use strict;
# B includes 14 files and 3821 lines. overhead subtracted with B::Stats::Minus
use B;
use B::Stats::Minus;
# XSLoader adds 0 files and 0 lines, already with B.
# Changed to DynaLoader
# Opcodes-0.10 adds 6 files and 5303-3821 lines: Carp, AutoLoader, subs
# Opcodes-0.11 adds 2 files and 4141-3821 lines: subs
# use Opcodes; # deferred to run-time below
our ($static, @runtime, $compiled);
my (%opt, $nops, $rops, @all_subs, $frag, %roots);
my ($c_count, $e_count, $r_count);

# check options
sub import {
  $DB::single = 1 if defined &DB::DB;
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

# collect subs and stashes before B is loaded
# XXX not yet used. we rather use B::Stats::Minus
sub _collect_env {
  %B_env = { 'B::Stats' => 1};
  _xs_collect_env() if $INC{'DynaLoader.pm'};
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
    push @all_subs, $_->ROOT
      for grep { _class($_) eq "CV" } $cv->PADLIST->ARRAY->ARRAY;
  }
  return unless ${$cv->START} and ${$cv->ROOT};
  $roots{$name} = $cv->ROOT;
};
sub B::SPECIAL::_mypush_starts{}

sub _walkops {
  my ($callback, $data) = @_;
  # _collect_env() unless %B_env;
  require 'B.pm';
  %roots  = ( '__MAIN__' =>  B::main_root()  );
  _walksymtable(\%main::,
	       '_mypush_starts',
	       sub {
		 return if scalar grep {$_[0] eq $_."::"} ('B::Stats');
		 1;
	       }, # Do not eat our own children!
	       '');
  push @all_subs, $_->ROOT
    for grep { _class($_) eq "CV" } B::main_cv->PADLIST->ARRAY->ARRAY;
  for $sub (keys %roots) {
    _walkoptree_simple($roots{$sub}, $callback, $data);
  }
  $sub = "__ANON__";
  for (@all_subs) {
    _walkoptree_simple($_, $callback, $data);
  }
}

sub _walkoptree_simple {
  my ($op, $callback, $data) = @_;
  $callback->($op,$data);
  if ($$op && ($op->flags & B::OPf_KIDS)) {
    for (my $kid = $op->first; $$kid; $kid = $kid->sibling) {
      _walkoptree_simple($kid, $callback, $data);
    }
  }
}

sub _walksymtable {
    my ($symref, $method, $recurse, $prefix) = @_;
    my ($sym, $ref, $fullname);
    no strict 'refs';
    $prefix = '' unless defined $prefix;
    while (($sym, $ref) = each %$symref) {
        $fullname = "*main::".$prefix.$sym;
	if ($sym =~ /::$/) {
	    $sym = $prefix . $sym;
	    if (B::svref_2object(\*$sym)->NAME ne "main::" &&
		$sym ne "<none>::" && &$recurse($sym))
	    {
               _walksymtable(\%$fullname, $method, $recurse, $sym);
	    }
	} else {
           B::svref_2object(\*$fullname)->$method();
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

  my $files = scalar keys %B_inc;
  my $lines = 0;
  for (values %B_inc) {
    print STDERR $_,"\n" if $opt{F};
    open IN, "<", "$_";
    # Todo: skip pod?
    while (<IN>) { chomp; s/#.*//; next if not length $_; $lines++; };
    close IN;
  }
  my %name = (
    'static compile-time' => 'c',
    'static end-time'     => 'e',
    'dynamic run-time'    => 'r'
    );
  my $key = $name{$name};
  $files -= $B::Stats::Minus::overhead{$key}{_files};
  $lines -= $B::Stats::Minus::overhead{$key}{_lines};
  $ops -= $B::Stats::Minus::overhead{$key}{_ops};
  print STDERR "\nB::Stats $name:\nfiles=$files\tlines=$lines\tops=$ops\n";
  return if $opt{t} and $opt{u};

  print STDERR "\nop name:\n";
  for (sort { $count->{name}->{$b} <=> $count->{name}->{$a} }
       keys %{$count->{name}}) {
    my $l = length $_;
    my $c = $count->{name}->{$_} - $B::Stats::Minus::overhead{$key}{$_};
    print STDERR $_, " " x (10-$l), "\t", $c, "\n";
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

  require DynaLoader;
  our @ISA = ('DynaLoader');
  DynaLoader::bootstrap('B::Stats', $VERSION);

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

1;
