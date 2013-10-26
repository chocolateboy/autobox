#!/usr/bin/env perl

use strict;
use warnings;
use blib;

# simplified version of the test case provided by Tomas Doran (t0m)
# https://rt.cpan.org/Ticket/Display.html?id=71777

{
    package Foo;
    use autobox;
    sub DESTROY {
        # silence this distracting (but expected) warning:
        # "(in cleanup) Can't call method "bar" on an undefined value at t/rt_71777.pl line 17 during global destruction."
        no warnings qw(misc);
        $_[0]->{bar}->bar
    }
}

{
    package Bar;
    sub bar { }
}

my $bar = bless {}, 'Bar';
my $foo = bless {}, 'Foo';

$foo->{bar} = $bar;
$bar->{foo} = $foo;
