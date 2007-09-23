package autobox;

use 5.008;
use strict;
use warnings;

use Carp qw(confess);
use XSLoader;
use Scope::Guard;

our $VERSION = '1.22';

XSLoader::load 'autobox', $VERSION;

############################################# PRIVATE ###############################################

# map builtin types to the package or namespace that handles them, or undef if (by default)
# that type should not be boxed; the full list of supported types is:
#
#     REF SCALAR LVALUE ARRAY HASH CODE GLOB FORMAT IO UNKNOWN
# 
# this map is exposed by the (undocumented) typemap method below, allowing subclasses to provide new
# defaults and/or allow a wider or narrower range of types to be autoboxed.

my $TYPEMAP = {
    SCALAR	=> 'SCALAR',
    ARRAY	=> 'ARRAY',
    HASH	=> 'HASH',
    CODE	=> 'CODE',
    UNDEF	=>  undef,
};

my $CACHE = {}; # hold a reference to the handlers hashes

sub _is_namespace ($) { $_[0] =~ /::$/ }

sub _universalize ($) {
    my $class = shift;
    return unless (defined $class);
    no strict 'refs';
    *{"$class\::can"} = sub { shift; UNIVERSAL::can($class, @_) }
    unless (*{"$class\::can"}{CODE});
    *{"$class\::isa"} = sub { shift; UNIVERSAL::isa($class, @_) }
    unless (*{"$class\::isa"}{CODE});
}

sub _debug ($) {
    my $handlers = shift;
    require Data::Dumper;
    no warnings qw(once);
    local ($|, $Data::Dumper::Indent, $Data::Dumper::Terse) = (1, 1, 1);
    print STDERR Data::Dumper::Dumper($handlers), $/;
}

############################################# PUBLIC (Methods) ###############################################

# this undocumented method allows subclasses to provide their own default bindings; see the notes above

sub typemap { $TYPEMAP }

sub import {
    my ($class, %args) = @_;
    my $handlers = {}; # custom typemap
    my $debug = delete $args{DEBUG};
    my $default = exists $args{DEFAULT} ? delete $args{DEFAULT} : '';
    my $typemap = $class->typemap();

    # fill in defaults for unhandled cases
    for my $key (keys %$typemap) {

	# skip explicit undefs
	next if ((exists $args{$key}) && (not(defined $args{$key})));

	if (exists $args{$key}) { # we know it's not undef
	    if ($args{$key} eq '') {
		$args{$key} = $typemap->{$key};
	    } # else: already defined
	} else {
	    if ((defined $default) && ($default eq '')) {
		$args{$key} = $typemap->{$key};
	    } else {
		$args{$key} = $default; # namespace expansion is handled below
	    }
	}
    }

    # sanity check %args, expand the namespace prefixes into package names and copy defined values to $handlers
    for my $key (keys %args) {
	confess ("unrecognised option: '", (defined $key ? $key : ''), "'") 
	    unless (exists $typemap->{$key});

	my $value = $args{$key};

	# The default typemap of UNDEF => undef (typically hoist into %args in the loop above)
	# ensures that UNDEF is never autoboxed unless an explicit package or namespace
	# is supplied
	next unless (defined $value);
	$handlers->{$key} = _is_namespace($value) ? "$value$key" : $value;
    }

    $^H |= 0x120000; # set HINT_LOCALIZE_HH + an unused bit to work a round a %^H bug
    $^H{autobox} = int($handlers);

    $CACHE->{$handlers} = $handlers; # hold a reference to the handlers hash

    _universalize($_) for (values %$handlers);

    if ($debug) {
	$debug = \&_debug unless (ref $debug eq 'CODE');
	$debug->($handlers);
    }

    my $sg = Scope::Guard->new(sub { Autobox::leavescope() });
    $^H{$sg} = $sg;

    Autobox::enterscope();
}

sub unimport {
    $^H &= ~0x120000;
    delete $^H{autobox};
}

1;

=pod

=head1 NAME

autobox - use builtin datatypes as first-class objects

=head1 SYNOPSIS

    use autobox;

    # call methods on builtin values and literals

    # integers

	my $range = 10->to(1); # [ 10, 9, 8, 7, 6, 5, 4, 3, 2, 1 ]

    # floats

	my $error = 3.1415927->minus(22/7)->abs();

    # strings

	my $uri = 'www.%s.com/foo.pl?arg=%s'->f($domain, $arg->escape());
	my $links = 'autobox'->google();

	my $word = 'rubicund';
	my $definition = $word->lookup_on_dictionary_dot_com();

	my $greeting = "Hello, World"->upper(); # "HELLO, WORLD"

	$greeting->to_lower(); # greeting is now "hello, world"
	$greeting->for_each(\&character_handler);

    # ARRAY refs

	my $schwartzian = [ @_ ]->map(...)->sort(...)->map(...);
	my $sd = [ 1, 8, 3, 3, 2, 9 ]->standard_deviation();

    # HASH refs

	{ alpha => 'beta', gamma => 'vlissides' }->for_each(...);

    # CODE refs

	my $plus_five = (\&add)->curry()->(5);
	my $minus_three = sub { $_[0] - $_[1] }->reverse->curry->(3);

    # can() and isa() work as expected

	if ("Hello, World"->can('foo')) ...
	if (3.1415927->isa('SCALAR')) ...

=head1 DESCRIPTION

The autobox pragma endows Perl's core datatypes with the capabilities of
first-class objects. This allows methods to be called on ARRAY refs,
HASH refs, CODE refs and raw scalars in exactly the same manner as blessed
references. The autoboxing is transparent: boxed values are not blessed
into their (user-defined) implementation class (unless the method elects to
bestow such a blessing) - they simply use its methods as though they are.

autobox is lexically scoped, and handlers (see below) for an outer scope
can be overridden or countermanded in a nested scope:

    {
	use autobox; # default handlers
	...
	{
	    use autobox SCALAR => 'MyScalar';
	    ...
	}
	# back to the default
	...
    }

Autoboxing can be turned off entirely by using the C<no> syntax:

    {
	use autobox;
	...
	no autobox;
	...
    }

- as well as by specifying a sole default value of undef (see below):

    use autobox DEFAULT => undef;

Autoboxing is not performed for barewords i.e. 

    my $foo = Foo->new();

and:

    my $foo = new Foo;

behave as expected.

In addition, it only covers named methods, so while this works:

    my $foobar = { foo => 'bar' }->some_method();

These don't:

    my $method1 = 'some_method';
    my $method2 = \&HASH::some_method;

    my $error1 = { foo => 'bar' }->$method1();
    my $error2 = { foo => 'bar' }->$method2();

The classes into which the core types are boxed are fully configurable.
By default, a method invoked on a non-object value is assumed to be
defined in a package whose name corresponds to the ref() type of that
value - or 'SCALAR' if the value is a non-reference.

Thus a vanilla:

    use autobox;

registers the following default handlers (for the current lexical scope):

    {
	SCALAR	=> 'SCALAR',
	ARRAY	=> 'ARRAY',
	HASH	=> 'HASH',
	CODE	=> 'CODE'
    }

Consequently:

    "hello, world"->upper()

would be invoked as:

    SCALAR::upper("hello, world")

while:

    [ 1 .. 10 ]->for_each(sub { ... })

resolves to:

    ARRAY::for_each([ 1 .. 10 ], sub { ... })

A mapping from the builtin type to the user-defined class can be specified
by passing a list of key/value bindings to the C<use autobox> statement.

The following example shows the range of valid arguments:

    use autobox SCALAR  => 'MyScalar'	    # package name
		ARRAY   => 'MyNamespace::', # package prefix (ending in '::')
		HASH    => '',		    # use the default i.e. HASH 
		CODE    => undef,	    # don't autobox this type
		UNDEF   => ...,		    # can take any of the 4 types above
		DEFAULT => ...,		    # can take any of the 4 types above
		DEBUG   => ...;		    # boolean or coderef

SCALAR, ARRAY, HASH, CODE, UNDEF and DEFAULT can take four different types of value:

=over

=item *

A package name e.g.

    use autobox SCALAR => 'MyScalar';

This overrides the default package - in this case SCALAR. All methods invoked on
literals or values of builtin type 'key' will be dispatched
as methods of the package specified in the corresponding 'value'.

If a package name is supplied for DEFAULT, it becomes the default package
for all unhandled cases. Thus:

    use autobox ARRAY	=> 'MyArray',
		DEFAULT => 'MyDefault';

will invoke ARRAY methods on MyArray and all other methods on MyDefault.

=item *

A namespace: this is a package prefix (up to and including the final '::')
to which the name of the default handler for this type will be appended:

Thus:

    use autobox ARRAY => 'Prelude::';

binds ARRAY types to the Prelude::ARRAY package.

As with the package name form, specifying a default namespace e.g.

    use autobox SCALAR	=> 'MyScalar',
		DEFAULT => 'MyNamespace::';

binds MyNamespace::ARRAY, MyNamespace::HASH &c. to the corresponding builtin
types.

=item *

An empty string: this is shorthand for the builtin type name. e.g.

    use autobox SCALAR	=> 'MyScalar',
		ARRAY	=> '',
	       	DEFAULT => 'MyDefault::';

is equivalent to:

    use autobox SCALAR	=> 'MyScalar'
		ARRAY	=> 'ARRAY',
		DEFAULT	=> 'MyDefault::';

which in turn is equivalent to:

    use autobox SCALAR	=> 'MyScalar'
		ARRAY	=> 'ARRAY',
		HASH	=> 'MyDefault::HASH',
		CODE	=> 'MyDefault::CODE';

If DEFAULT is set to an empty string (as it is by default),
it fills in the default type for all the unhandled cases e.g.

    use autobox SCALAR	=> 'MyScalar',
		CODE	=> 'MyCode',
	       	DEFAULT => '';

is equivalent to:

    use autobox SCALAR	=> 'MyScalar',
		CODE	=> 'MyCode',
		ARRAY	=> 'ARRAY',
		HASH	=> 'HASH';

=item *

undef: this disables autoboxing for the specified type, or all unhandled types
in the case of DEFAULT.

=back

In addition to the SCALAR, ARRAY, HASH, CODE and DEFAULT options above,
there are two additional options: UNDEF and DEBUG.

=head2 UNDEF

The pseudotype, UNDEF, can be used to autobox undefined values. These are
not autoboxed by default (i.e. the default value is undef):

This doesn't work:

    use autobox;

    undef->foo() # runtime error

This works:

    use autobox UNDEF => 'MyPackage'; 

    undef->foo(); # ok

So does this:

    use autobox UNDEF => 'MyNamespace::'; 

    undef->foo(); # ok

=head2 DEBUG

DEBUG exposes the current handlers by means of a callback, or a
static debugging function.

This can be useful if one wishes to see the computed bindings
in 'longhand'.

Debugging is ignored if the value corresponding to the DEBUG key is false.

If the value is a CODE ref, then this sub is called with a reference to
the HASH containing the computed handlers for the current scope.

Finally, if DEBUG is true but not a CODE ref, the handlers are dumped
to STDERR.

Thus:

    use autobox DEBUG => 1, ...

or

    use autobox DEBUG => sub { ... }, ...

or

    sub my_callback ($) {
	my $hashref = shift;
	...
    }

    use autobox DEBUG => \&my_callback, ...

=head1 CAVEATS

Due to Perl's precedence rules some autoboxed literals may need to be
parenthesized:

For instance, while this works:

    my $curried = sub { ... }->curry();

this doesn't:

    my $curried = \&foo->curry();

The solution is to wrap the reference in parentheses:

    my $curried = (\&foo)->curry();

The same applies for signed integer and float literals:

    # this works
    my $range = 10->to(1);

    # this doesn't work
    my $range = -10->to(10);

    # this works
    my $range = (-10)->to(10);

Perl's special-casing for the C<print BLOCK ...> syntax
(see perlsub) means that C<print { expression() } ...>
(where the curly brackets denote an anonymous HASH ref)
may require some further disambiguation:

    # this works (
    print { foo => 'bar' }->foo();

    # and this
    print { 'foo', 'bar' }->foo();

    # and even this
    print { 'foo', 'bar', @_ }->foo();

    # but this doesn't
    print { @_ }->foo() ? 1 : 0 

In the latter case, the solution is to supply something
other than a HASH ref literal as the first argument
to print():

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

Although C<can> and C<isa> are "overloaded" for autoboxed values, the C<VERSION> method isn't.
Thus, while these work:

	[ ... ]->can('pop')

	3.1415->isa('MyScalar')

This doesn't:

	use MyScalar 1.23;

	use autobox SCALAR => MyScalar;

	print "Hello, World"->VERSION(), $/;

Though, of course:

	print MyScalar->VERSION(), $/;

and
	
	print $MyScalar::VERSION, $/;

continue to work.

This is due to a limitation in perl's implementation of C<use> and C<no>.
Likewise, C<import> and C<unimport> are unaffected by the autobox pragma:

	'Foo'->import() # equivalent to Foo->import() rather than MyScalar->import('Foo')

	[]->import()  # error: Can't call method "import" on unblessed reference
	
=head1 VERSION

1.22

=head1 SEE ALSO

=over

=item * L<Moose::Autobox>

=item * L<autobox::Core|autobox::Core>

=item * L<Perl6::Contexts|Perl6::Contexts>

=item * L<Shell::Autobox|Shell::Autobox>

=item * L<Scalar::Properties|Scalar::Properties>

=item * L<Set::Array|Set::Array>

=back

=head1 AUTHOR
    
chocolateboy: <chocolate.boy@email.com>

=head1 COPYRIGHT

Copyright (c) 2003-2007, chocolateboy.

This module is free software. It may be used, redistributed
and/or modified under the same terms as Perl itself.

=cut
