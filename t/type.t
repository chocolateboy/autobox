#!/usr/bin/env perl

use strict;
use warnings;

use Test::More tests => 13;

use autobox DEFAULT => __PACKAGE__, UNDEF => __PACKAGE__;

sub type { autobox->type(shift) }

my @array;
my %hash;
my $sub = sub {};

is(42->type, 'INTEGER');
is(3.1415927->type, 'FLOAT');
is(''->type, 'STRING');
is('Hello, world!'->type, 'STRING');
is(undef->type, 'UNDEF');
is([]->type, 'ARRAY');
is(undef->type, 'UNDEF');
is(@array->type, 'ARRAY');
is(%hash->type, 'HASH');
is((\&type)->type, 'CODE');
is($sub->type, 'CODE');

my $was_int = 42;
my $was_float = 3.1415927;

$was_int = 'Hello';
$was_float = 'World';

is($was_int->type, 'STRING');
is($was_float->type, 'STRING');
