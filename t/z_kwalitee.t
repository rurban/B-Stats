# -*- perl -*-
use strict;
use warnings;

use Test::More;

plan skip_all => 'This test is only run for the module author'
    unless -d '.git' || $ENV{IS_MAINTAINER};

eval { 
  require Test::Kwalitee; 
  Test::Kwalitee->import( 
    tests => [ qw( -use_strict -has_test_pod -has_test_pod_coverage )]);
};
plan skip_all => "Test::Kwalitee needed for testing kwalitee"
    if $@;
