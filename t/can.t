#!/usr/bin/env perl

# confirm that `can` overrides work via $native->autobox_class->can(...)

package CanFoo; # custom `can`

sub can { $_[1] eq 'foo' }

package CanBar; # default `can`

sub bar { __PACKAGE__ }

use strict;
use warnings;

use Test::More tests => 12;

{
    use autobox SCALAR => 'CanFoo';

    ok(42->autobox_class->can('foo'), '$can_foo->autobox_class->can("foo") == true');
    ok(not(42->autobox_class->can('bar')), '$can_foo->autobox_class->can("bar") == false');
    ok(not(42->autobox_class->can('baz')), '$can_foo->autobox_class->can("baz") == false');
}

{
    use autobox SCALAR => 'CanBar';

    ok(42->autobox_class->can('bar'), '$can_bar->autobox_class->can("bar") == true');
    ok(not(42->autobox_class->can('foo')), '$can_bar->autobox_class->can("foo") == false');
    ok(not(42->autobox_class->can('baz')), '$can_bar->autobox_class->can("baz") == false');
}

{
    # the custom `can` in CanFoo should pre-empt the default `can` in CanBar
    use autobox SCALAR => [ 'CanFoo', 'CanBar' ];

    ok(42->autobox_class->can('foo'), '$can_merged_1->autobox_class->can("foo") == true');
    ok(not(42->autobox_class->can('bar')), '$can_merged_1->autobox_class->can("bar") == false');
    ok(not(42->autobox_class->can('baz')), '$can_merged_1->autobox_class->can("baz") == false');
}

{
    # the default `can` in CanBar should fall back to the custom `can` in CanFoo
    use autobox SCALAR => [ 'CanBar', 'CanFoo' ];

    ok(42->autobox_class->can('foo'), '$can_merged_2->autobox_class->can("foo") == true');
    ok(not(42->autobox_class->can('bar')), '$can_merged_2->autobox_class->can("bar") == false');
    ok(not(42->autobox_class->can('baz')), '$can_merged_2->autobox_class->can("baz") == false');
}
