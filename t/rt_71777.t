#!/usr/bin/env perl

use strict;
use warnings;
use blib;

# simplified version of the test case provided by Tomas Doran (t0m)
# https://rt.cpan.org/Ticket/Display.html?id=71777

print '1..1', $/;

{
    package Foo;
    use autobox;
    sub DESTROY {
        # confirm a method compiled under "use autobox" doesn't segfault when
        # called during global destruction. the "Can't call method" error is
        # raised by perl's method_named function (pp_method_named), which means
        # our implementation correctly delegated to it, which means our version didn't
        # segfault by trying to access the pointer table after it's been freed
        eval { $_[0]->{bar}->bar };

        if (not($@) || ($@ =~ /Can't call method "bar" on an undefined value/)) {
            print 'ok 1', $/;
        } else {
            print 'not ok 1', $/;
        }
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

