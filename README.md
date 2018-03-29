# autobox

[![Build Status](https://secure.travis-ci.org/chocolateboy/autobox.svg)](http://travis-ci.org/chocolateboy/autobox)
[![CPAN Version](https://badge.fury.io/pl/autobox.svg)](http://badge.fury.io/pl/autobox)
[![License](https://img.shields.io/badge/license-artistic-blue.svg)](https://github.com/chocolateboy/autobox/blob/master/LICENSE.md)

<!-- START doctoc generated TOC please keep comment here to allow auto update -->
<!-- DON'T EDIT THIS SECTION, INSTEAD RE-RUN doctoc TO UPDATE -->

- [NAME](#name)
- [SYNOPSIS](#synopsis)
- [DESCRIPTION](#description)
- [OPTIONS](#options)
  - [DEFAULT](#default)
  - [UNDEF](#undef)
  - [NUMBER, SCALAR and UNIVERSAL](#number-scalar-and-universal)
  - [DEBUG](#debug)
- [METHODS](#methods)
  - [import](#import)
- [UNIVERSAL METHODS FOR AUTOBOXED TYPES](#universal-methods-for-autoboxed-types)
  - [autobox_class](#autobox_class)
- [EXPORTS](#exports)
  - [type](#type)
- [CAVEATS](#caveats)
  - [Performance](#performance)
  - [Gotchas](#gotchas)
    - [Precedence](#precedence)
    - [print BLOCK](#print-block)
    - [eval EXPR](#eval-expr)
    - [Operator Overloading](#operator-overloading)
- [VERSION](#version)
- [SEE ALSO](#see-also)
- [AUTHOR](#author)
- [COPYRIGHT AND LICENSE](#copyright-and-license)

<!-- END doctoc generated TOC please keep comment here to allow auto update -->

# NAME

autobox - call methods on native types

# SYNOPSIS

```perl
use autobox;

# integers

    my $range = 10->to(1); # [ 10, 9, 8, 7, 6, 5, 4, 3, 2, 1 ]

# floats

    my $error = 3.1415927->minus(22/7)->abs();

# strings

    my @list = 'SELECT * FROM foo'->list();
    my $greeting = "Hello, world!"->upper(); # "HELLO, WORLD!"

    $greeting->for_each(\&character_handler);

# arrays and array refs

    my $schwartzian = @_->map(...)->sort(...)->map(...);
    my $hash = [ 'SELECT * FROM foo WHERE id IN (?, ?)', 1, 2 ]->hash();

# hashes and hash refs

    { alpha => 'beta', gamma => 'vlissides' }->for_each(...);
    %hash->keys();

# code refs

    my $plus_five = (\&add)->curry()->(5);
    my $minus_three = sub { $_[0] - $_[1] }->reverse->curry->(3);

# can, isa, VERSION, import and unimport can be accessed via autobox_class

    42->autobox_class->isa('MyNumber')
    say []->autobox_class->VERSION
```

# DESCRIPTION

The `autobox` pragma allows methods to be called on integers, floats, strings, arrays,
hashes, and code references in exactly the same manner as blessed references.

Autoboxing is transparent: values are not blessed into their (user-defined)
implementation class (unless the method elects to bestow such a blessing) - they simply
use its methods as though they are.

The classes (packages) into which the native types are boxed are fully configurable.
By default, a method invoked on a non-object value is assumed to be
defined in a class whose name corresponds to the `ref()` type of that
value - or SCALAR if the value is a non-reference.

This mapping can be overridden by passing key/value pairs to the `use autobox`
statement, in which the keys represent native types, and the values
their associated classes.

As with regular objects, autoboxed values are passed as the first argument of the specified method.
Consequently, given a vanilla `use autobox`:

```perl
"Hello, world!"->upper()
```

is invoked as:

```perl
SCALAR::upper("hello, world!")
```

while:

```perl
[ 1 .. 10 ]->for_each(sub { ... })
```

resolves to:

```perl
ARRAY::for_each([ 1 .. 10 ], sub { ... })
```

Values beginning with the array `@` and hash `%` sigils are passed by reference, i.e. under the default bindings:

```perl
@array->join(', ')
@{ ... }->length()
%hash->keys()
%$hash->values()
```

are equivalent to:

```perl
ARRAY::join(\@array, ', ')
ARRAY::length(\@{ ... })
HASH::keys(\%hash)
HASH::values(\%$hash)
```

Multiple `use autobox` statements can appear in the same scope. These are merged both "horizontally" (i.e.
multiple classes can be associated with a particular type) and "vertically" (i.e. multiple classes can be associated
with multiple types).

Thus:

```perl
use autobox SCALAR => 'Foo';
use autobox SCALAR => 'Bar';
```

\- associates SCALAR types with a synthetic class whose `@ISA` includes both `Foo` and `Bar` (in that order).

Likewise:

```perl
use autobox SCALAR => 'Foo';
use autobox SCALAR => 'Bar';
use autobox ARRAY  => 'Baz';
```

and

```perl
use autobox SCALAR => [ 'Foo', 'Bar' ];
use autobox ARRAY  => 'Baz';
```

\- bind SCALAR types to the `Foo` and `Bar` classes and ARRAY types to `Baz`.

`autobox` is lexically scoped, and bindings for an outer scope
can be extended or countermanded in a nested scope:

```perl
{
    use autobox; # default bindings: autobox all native types
    ...

    {
        # appends 'MyScalar' to the @ISA associated with SCALAR types
        use autobox SCALAR => 'MyScalar';
        ...
    }

    # back to the default (no MyScalar)
    ...
}
```

Autoboxing can be turned off entirely by using the `no` syntax:

```perl
{
    use autobox;
    ...
    no autobox;
    ...
}
```

\- or can be selectively disabled by passing arguments to the `no autobox` statement:

```perl
use autobox; # default bindings

no autobox qw(SCALAR);

[]->foo(); # OK: ARRAY::foo([])

"Hello, world!"->bar(); # runtime error
```

Autoboxing is not performed for barewords i.e.

```perl
my $foo = Foo->new();
```

and:

```perl
my $foo = new Foo;
```

behave as expected.

Methods are called on native types by means of the [arrow operator](https://metacpan.org/pod/perlop#The-Arrow-Operator). As with
regular objects, the right hand side of the operator can either be a bare method name or a variable containing
a method name or subroutine reference. Thus the following are all valid:

```perl
sub method1 { ... }
my $method2 = 'some_method';
my $method3 = sub { ... };
my $method4 = \&some_method;

" ... "->method1();
[ ... ]->$method2();
{ ... }->$method3();
sub { ... }->$method4();
```

A native type is only associated with a class if the type => class mapping
is supplied in the `use autobox` statement. Thus the following will not work:

```perl
use autobox SCALAR => 'MyScalar';

@array->some_array_method();
```

\- as no class is specified for the ARRAY type. Note: the result of calling a method
on a native type that is not associated with a class is the usual runtime error message:

```perl
Can't call method "some_array_method" on unblessed reference at ...
```

As a convenience, there is one exception to this rule. If `use autobox` is invoked with no arguments
(ignoring the DEBUG option) the four main native types are associated with classes of the same name.

Thus:

```perl
use autobox;
```

\- is equivalent to:

```perl
use autobox {
    SCALAR => 'SCALAR',
    ARRAY  => 'ARRAY',
    HASH   => 'HASH',
    CODE   => 'CODE',
}
```

This facilitates one-liners and prototypes:

```perl
use autobox;

sub SCALAR::split { [ split '', $_[0] ] }
sub ARRAY::length { scalar @{$_[0]} }

print "Hello, world!"->split->length();
```

However, using these default bindings is not recommended as there's no guarantee that another
piece of code won't trample over the same namespace/methods.

# OPTIONS

A mapping from native types to their user-defined classes can be specified
by passing a hashref or a list of key/value pairs to the `use autobox` statement.

The following example shows the range of valid arguments:

```perl
use autobox {
    SCALAR    => 'MyScalar'                     # class name
    ARRAY     => 'MyNamespace::',               # class prefix (ending in '::')
    HASH      => [ 'MyHash', 'MyNamespace::' ], # one or more class names and/or prefixes
    CODE      => ...,                           # any of the 3 value types above
    INTEGER   => ...,                           # any of the 3 value types above
    FLOAT     => ...,                           # any of the 3 value types above
    NUMBER    => ...,                           # any of the 3 value types above
    STRING    => ...,                           # any of the 3 value types above
    UNDEF     => ...,                           # any of the 3 value types above
    UNIVERSAL => ...,                           # any of the 3 value types above
    DEFAULT   => ...,                           # any of the 3 value types above
    DEBUG     => ...                            # boolean or coderef
}
```

The INTEGER, FLOAT, NUMBER, STRING, SCALAR, ARRAY, HASH, CODE, UNDEF, DEFAULT and UNIVERSAL options can take
three different types of value:

- A class name e.g.

```perl
use autobox INTEGER => 'MyInt';
```

This binds the specified native type to the specified class. All methods invoked on
values of type `key` will be dispatched as methods of the class specified in
the corresponding `value`.

- A namespace: this is a class prefix (up to and including the final '::')
to which the specified type name (INTEGER, FLOAT, STRING &c.) will be appended:

Thus:

```perl
use autobox ARRAY => 'Prelude::';
```

is equivalent to:

```perl
use autobox ARRAY => 'Prelude::ARRAY';
```

- A reference to an array of class names and/or namespaces. This associates multiple classes with the
specified type.

## DEFAULT

The `DEFAULT` option specifies bindings for any of the four default types (SCALAR, ARRAY, HASH and CODE)
not supplied in the `use autobox` statement. As with the other options, the `value` corresponding to
the `DEFAULT` `key` can be a class name, a namespace, or a reference to an array containing one or
more class names and/or namespaces.

Thus:

```perl
use autobox {
    STRING  => 'MyString',
    DEFAULT => 'MyDefault',
}
```

is equivalent to:

```perl
use autobox {
    STRING  => 'MyString',
    SCALAR  => 'MyDefault',
    ARRAY   => 'MyDefault',
    HASH    => 'MyDefault',
    CODE    => 'MyDefault',
}
```

Which in turn is equivalent to:

```perl
use autobox {
    INTEGER => 'MyDefault',
    FLOAT   => 'MyDefault',
    STRING  => [ 'MyString', 'MyDefault' ],
    ARRAY   => 'MyDefault',
    HASH    => 'MyDefault',
    CODE    => 'MyDefault',
}
```

Namespaces in DEFAULT values have the default type name appended, which, in the case of defaulted SCALAR types,
is SCALAR rather than INTEGER, FLOAT &c.

Thus:

```perl
use autobox {
    ARRAY   => 'MyArray',
    HASH    => 'MyHash',
    CODE    => 'MyCode',
    DEFAULT => 'MyNamespace::',
}
```

is equivalent to:

```perl
use autobox {
    INTEGER => 'MyNamespace::SCALAR',
    FLOAT   => 'MyNamespace::SCALAR',
    STRING  => 'MyNamespace::SCALAR',
    ARRAY   => 'MyArray',
    HASH    => 'MyArray',
    CODE    => 'MyCode',
}
```

Any of the four default types can be exempted from defaulting to the DEFAULT value by supplying a value of undef:

```perl
use autobox {
    HASH    => undef,
    DEFAULT => 'MyDefault',
};

42->foo; # ok: MyDefault::foo
[]->bar; # ok: MyDefault::bar

%INC->baz; # not ok: runtime error
```

## UNDEF

The pseudotype, UNDEF, can be used to autobox undefined values. These are not autoboxed by default.

This doesn't work:

```perl
use autobox;

undef->foo() # runtime error
```

This works:

```perl
use autobox UNDEF => 'MyUndef';

undef->foo(); # ok
```

So does this:

```perl
use autobox UNDEF => 'MyNamespace::';

undef->foo(); # ok
```

## NUMBER, SCALAR and UNIVERSAL

The virtual types NUMBER, SCALAR and UNIVERSAL function as macros or shortcuts which create
bindings for their subtypes. The type hierarchy is as follows:

```
UNIVERSAL -+
           |
           +- SCALAR -+
           |          |
           |          +- NUMBER -+
           |          |          |
           |          |          +- INTEGER
           |          |          |
           |          |          +- FLOAT
           |          |
           |          +- STRING
           |
           +- ARRAY
           |
           +- HASH
           |
           +- CODE
```

Thus:

```perl
use autobox NUMBER => 'MyNumber';
```

is equivalent to:

```perl
use autobox {
    INTEGER => 'MyNumber',
    FLOAT   => 'MyNumber',
}
```

And:

```perl
use autobox SCALAR => 'MyScalar';
```

is equivalent to:

```perl
use autobox {
    INTEGER => 'MyScalar',
    FLOAT   => 'MyScalar',
    STRING  => 'MyScalar',
}
```

Virtual types can also be passed to `unimport` via the `no autobox` syntax. This disables autoboxing
for the corresponding subtypes e.g.

```perl
no autobox qw(NUMBER);
```

is equivalent to:

```perl
no autobox qw(INTEGER FLOAT);
```

Virtual type bindings can be mixed with ordinary bindings to provide fine-grained control over
inheritance and delegation. For instance:

```perl
use autobox {
    INTEGER => 'MyInteger',
    NUMBER  => 'MyNumber',
    SCALAR  => 'MyScalar',
}
```

would result in the following bindings:

```perl
42->foo             -> [ MyInteger, MyNumber, MyScalar ]
3.1415927->bar      -> [ MyNumber, MyScalar ]
"Hello, world!->baz -> [ MyScalar ]
```

Note that DEFAULT bindings take precedence over virtual type bindings i.e.

```perl
use autobox {
    UNIVERSAL => 'MyUniversal',
    DEFAULT   => 'MyDefault', # default SCALAR, ARRAY, HASH and CODE before UNIVERSAL
}
```

is equivalent to:

```perl
use autobox {
    INTEGER => [ 'MyDefault', 'MyUniversal' ],
    FLOAT   => [ 'MyDefault', 'MyUniversal' ], # ... &c.
}
```

## DEBUG

`DEBUG` exposes the current bindings for the scope in which `use autobox` is called by means
of a callback, or a static debugging function.

This allows the computed bindings to be seen in "longhand".

The option is ignored if the value corresponding to the `DEBUG` key is false.

If the value is a CODE ref, then this sub is called with a reference to
the hash containing the computed bindings for the current scope.

Finally, if `DEBUG` is true but not a CODE ref, the bindings are dumped
to STDERR.

Thus:

```perl
use autobox DEBUG => 1, ...
```

or

```perl
use autobox DEBUG => sub { ... }, ...
```

or

```perl
sub my_callback ($) {
    my $hashref = shift;
    ...
}

use autobox DEBUG => \&my_callback, ...
```

# METHODS

## import

This method sets up `autobox` bindings for the current lexical scope. It can be used to implement
`autobox` extensions i.e. lexically-scoped modules that provide `autobox` bindings for one or more
native types without requiring calling code to `use autobox`.

This is done by subclassing `autobox` and overriding `import`. This allows extensions to effectively
translate `use MyModule` into a bespoke `use autobox` call. e.g.:

```perl
package String::Trim;

use base qw(autobox);

sub import {
    my $class = shift;
    $class->SUPER::import(
        STRING => 'String::Trim::String'
    );
}

package String::Trim::String;

sub trim {
    my $string = shift;
    $string =~ s/^\s+//;
    $string =~ s/\s+$//;
    $string;
}

1;
```

Note that `trim` is defined in an auxiliary class rather than in `String::Trim` itself to prevent
`String::Trim`'s own methods (i.e. the methods it inherits from `autobox`) being exposed to `STRING` types.

This module can now be used without a `use autobox` statement to enable the `trim` method in the current
lexical scope. e.g.:

```perl
#!/usr/bin/env perl

use String::Trim;

print "  Hello, world!  "->trim();
```

# UNIVERSAL METHODS FOR AUTOBOXED TYPES

## autobox_class

`autobox` adds a single method to all autoboxed types: `autobox_class`. This can be used to
call `can`, `isa`, `VERSION`, `import` and `unimport`. e.g.

```perl
if (sub { ... }->autobox_class->can('curry')) ...
if (42->autobox_class->isa('SCALAR')) ...
```

Note: `autobox_class` should **always** be used when calling these methods. The behaviour when
these methods are called directly on the native type e.g.:

```perl
42->can('foo')
42->isa('Bar')
42->VERSION
```

\- is undefined.

# EXPORTS

## type

`autobox` includes an additional module, `autobox::universal`, which exports a single subroutine, `type`.

This sub returns the type of its argument within `autobox` (which is essentially longhand for the type names
used within perl). This value is used by `autobox` to associate a method invocant with its designated classes. e.g.

```perl
use autobox::universal qw(type);

type("42")  # STRING
type(42)    # INTEGER
type(42.0)  # FLOAT
type(undef) # UNDEF
```

`autobox::universal` is loaded automatically by `autobox`, and, as its name suggests, can be used to install
a universal `type` method for autoboxed values e.g.

```perl
use autobox UNIVERSAL => 'autobox::universal';

42->type        # INTEGER
3.1415927->type # FLOAT
%ENV->type      # HASH
```

# CAVEATS

## Performance

Calling

```perl
"Hello, world!"->length()
```

is slightly slower than the equivalent method call on a string-like object, and significantly slower than

```perl
length("Hello, world!")
```

## Gotchas

### Precedence

Due to Perl's precedence rules, some autoboxed literals may need to be parenthesized:

For instance, while this works:

```perl
my $curried = sub { ... }->curry();
```

this doesn't:

```perl
my $curried = \&foo->curry();
```

The solution is to wrap the reference in parentheses:

```perl
my $curried = (\&foo)->curry();
```

The same applies for signed integer and float literals:

```perl
# this works
my $range = 10->to(1);

# this doesn't work
my $range = -10->to(10);

# this works
my $range = (-10)->to(10);
```

### print BLOCK

Perl's special-casing for the `print BLOCK ...` syntax (see [perlsub](https://metacpan.org/pod/perlsub)) means that `print { expression() } ...`
(where the curly brackets denote an anonymous HASH ref) may require some further disambiguation:

```perl
# this works
print { foo => 'bar' }->foo();

# and this
print { 'foo', 'bar' }->foo();

# and even this
print { 'foo', 'bar', @_ }->foo();

# but this doesn't
print { @_ }->foo() ? 1 : 0
```

In the latter case, the solution is to supply something
other than a HASH ref literal as the first argument
to `print()`:

```perl
# e.g.
print STDOUT { @_ }->foo() ? 1 : 0;

# or
my $hashref = { @_ };
print $hashref->foo() ? 1 : 0;

# or
print '', { @_ }->foo() ? 1 : 0;

# or
print '' . { @_ }->foo() ? 1 : 0;

# or even
{ @_ }->print_if_foo(1, 0);
```

### eval EXPR

Like most pragmas, `autobox` performs operations at compile time, and,
as a result, runtime string `eval`s are not executed within its scope i.e. this
doesn't work:

```perl
use autobox;

eval "42->foo";
```

The workaround is to use `autobox` within the `eval` e.g.

```perl
eval <<'EOS';
    use autobox;
    42->foo();
EOS
```

Note that the `eval BLOCK` form works as expected:

```perl
use autobox;

eval { 42->foo() }; # OK
```

### Operator Overloading

Operator overloading via the [overload](https://metacpan.org/pod/overload) pragma doesn't (automatically) work. `autobox`
works by lexically overriding the [arrow operator](https://metacpan.org/pod/perlop#The-Arrow-Operator).
It doesn't bless native types into objects, so overloading — or any other kind of "magic" which depends on values being
blessed — doesn't apply.

# VERSION

2.85

# SEE ALSO

- [autobox::Core](https://metacpan.org/pod/autobox::Core)
- [Moose::Autobox](https://metacpan.org/pod/Moose::Autobox)
- [perl5i](https://metacpan.org/pod/perl5i)
- [Scalar::Properties](https://metacpan.org/pod/Scalar::Properties)

# AUTHOR

[chocolateboy](mailto:chocolate@cpan.org)

# COPYRIGHT AND LICENSE

Copyright © 2008-2016 by chocolateboy.

autobox is free software; you can redistribute it and/or modify it under the terms of the
[Artistic License 2.0](http://www.opensource.org/licenses/artistic-license-2.0.php).
