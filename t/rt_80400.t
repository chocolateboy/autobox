#!/usr/bin/env perl

# Thanks to Tokuhiro Matsuno for the test case and patch
# https://rt.cpan.org/Ticket/Display.html?id=80400

use strict;
use warnings;

use Test::More;

my $X;

END { $X->() }

use autobox INTEGER => __PACKAGE__;

sub test {
    is_deeply(\@_, [ 1, 42 ], 'autoboxed method called in END block');
    done_testing;
};

$X = sub { 1->test(42) };
