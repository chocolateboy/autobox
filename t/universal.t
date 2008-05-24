#!/usr/bin/env perl

use strict;
use warnings;

use Test::More tests => 32;

my $undef;
my $integer = 42;
my $float = 3.1415927;
my $string = 'Hello, world!';
my @array;
my %hash;
my $sub = sub {};
my $type = \&autobox::universal::type;
my $eundef = qr{^Can't call method "can" on an undefined value\b};

{
    use autobox UNIVERSAL => 'autobox::universal';

    # confirm that UNIVERSAL doesn't include UNDEF if UNDEF is not explicitly bound
    eval { is(undef->can('type'), $type) };
    like ($@, $eundef);

    eval { is($undef->can('type'), $type) };
    like ($@, $eundef);

    is(42->can('type'), $type);
    is(42->type, 'INTEGER');
    is($integer->can('type'), $type);
    is($integer->type, 'INTEGER');
    is(3.1415927->can('type'), $type);
    is(3.1415927->type, 'FLOAT');
    is($float->can('type'), $type);
    is(3.1415927->type, 'FLOAT');
    is(''->can('type'), $type);
    is(''->type, 'STRING');
    is('Hello, world!'->can('type'), $type);
    is('Hello, world!'->type, 'STRING');
    is($string->can('type'), $type);
    is($string->type, 'STRING');
    is([]->can('type'), $type);
    is([]->type, 'ARRAY');
    is(@array->can('type'), $type);
    is(@array->type, 'ARRAY');
    is({}->can('type'), $type);
    is({}->type, 'HASH');
    is(%hash->can('type'), $type);
    is(%hash->type, 'HASH');
    is((\&type)->can('type'), $type);
    is((\&type)->type, 'CODE');
    is($sub->can('type'), $type);
    is($sub->type, 'CODE');

    # add support for UNDEF
    use autobox UNDEF => 'autobox::universal';

    is(undef->can('type'), $type);
    is(undef->type, 'UNDEF');
    is($undef->can('type'), $type);
    is($undef->type, 'UNDEF');
}
