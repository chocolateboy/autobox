#!/usr/bin/env perl

package Left;

sub left { __PACKAGE__ }
sub both { __PACKAGE__ }

package Right;

sub right { __PACKAGE__ }
sub both { __PACKAGE__ }

package main;

use strict;   # global
use warnings; # global

use Test::More tests => 32;

{
    use autobox SCALAR => [ qw(Left Right) ];

    ok(42->isa('Left'), 'LR1: isa Left');
    ok(42->isa('Right'), 'LR1: isa Right');

    ok(42->can('left'), 'LR1: can left');
    ok(42->can('both'), 'LR1: can both');
    ok(42->can('right'), 'LR1: can right');

    is(42->left, 'Left', 'LR1: left');
    is(42->both, 'Left', 'LR1: both');
    is(42->right, 'Right', 'LR1: right');
}

{
    use autobox SCALAR => 'Left';
    use autobox SCALAR => 'Right';

    ok(42->isa('Left'), 'LR2: isa Left');
    ok(42->isa('Right'), 'LR2: isa Right');

    ok(42->can('left'), 'LR2: can left');
    ok(42->can('both'), 'LR2: can both');
    ok(42->can('right'), 'LR2: can right');

    is(42->left, 'Left', 'LR2: left');
    is(42->both, 'Left', 'LR2: both');
    is(42->right, 'Right', 'LR2: right');
}

{
    use autobox SCALAR => [ qw(Right Left) ];

    ok(42->isa('Left'), 'RL1: isa Left');
    ok(42->isa('Right'), 'RL1: isa Right');

    ok(42->can('left'), 'RL1: can left');
    ok(42->can('both'), 'RL1: can both');
    ok(42->can('right'), 'RL1: can right');

    is(42->left, 'Left', 'RL1: left');
    is(42->both, 'Right', 'RL1: both');
    is(42->right, 'Right', 'RL1: right');
}

{
    use autobox SCALAR => 'Right';
    use autobox SCALAR => 'Left';

    ok(42->isa('Left'), 'RL2: isa Left');
    ok(42->isa('Right'), 'RL2: isa Right');

    ok(42->can('left'), 'RL2: can left');
    ok(42->can('both'), 'RL2: can both');
    ok(42->can('right'), 'RL2: can right');

    is(42->left, 'Left', 'RL2: left');
    is(42->both, 'Right', 'RL2: both');
    is(42->right, 'Right', 'RL2: right');
}
