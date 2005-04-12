package autobox;

use 5.006001;
use strict;
use warnings;

use XSLoader;
use Scope::Guard;

our $VERSION = '1.00';
our $cache = {};

XSLoader::load 'autobox', $VERSION;

END { Autobox::cleanup() }

# the returned hashref should provide an entry for all the supported types
# subclasses can override this to provide different semantics
# TODO: document this

sub typemap {
	# the full list is: qw(REF SCALAR LVALUE ARRAY HASH CODE GLOB FORMAT IO UNKNOWN)
	{ SCALAR => 'SCALAR', ARRAY => 'ARRAY', HASH => 'HASH', CODE => 'CODE', UNDEF => undef }
}

sub report ($) {
	my $handlers = shift;
	require Data::Dumper;
	local ($|, $Data::Dumper::Indent, $Data::Dumper::Terse) = (1, 1, 1);
	print STDERR Data::Dumper::Dumper($handlers), $/;
}

sub universalize ($) {
	my $class = shift;
	return unless (defined $class);
	no strict 'refs';
	*{"$class\::can"} = sub { shift; UNIVERSAL::can($class, @_) }
		unless (*{"$class\::can"}{CODE});
	*{"$class\::isa"} = sub { shift; UNIVERSAL::isa($class, @_) }
		unless (*{"$class\::isa"}{CODE});
	*{"$class\::VERSION"} = sub { shift; UNIVERSAL::VERSION($class, @_) } # hmm...
		unless (*{"$class\::VERSION"}{CODE});
}

sub is_namespace ($) { $_[0] eq '' or ($_[0] =~ /::$/) }

sub import {
	my $class = shift;
	my $handlers = { }; # custom typemap
	my $types = $class->typemap(); # default typemap
	my $report;

	if (scalar @_) {
		my %args = @_;
		my %unhandled = %$types;
		my $default = exists $args{DEFAULT} ? delete $args{DEFAULT} : '';

		if ($report = delete $args{REPORT}) { # REPORT => 1 : print to STDERR
			$report = \&report unless (ref $report eq 'CODE');
		}

		for my $key (keys %args) {
			die ("autobox: unrecognised type: '", (defined $key ? $key : ''), "'") 
				unless (exists $types->{$key});

			delete $unhandled{$key}; # delete before iterating

			my $value = $args{$key};

			next unless (defined $value);

			$handlers->{$key} = is_namespace($value) ? "$value$key" : $value;
		}

		if (defined $default) {
			my $default_is_namespace = is_namespace($default);
			for my $key (keys %unhandled) {
				$handlers->{$key} = $default_is_namespace ? "$default$key" : $default;
			}
		}

	} else {
		# isolate from $types in case monkey business occurs in a user-supplied report handler
		$handlers = { %$types };
	}

	$^H |= 0x20000;
	$^H{autobox} = int($handlers);

	$cache->{$handlers} = $handlers;

	universalize($_) for (values %$handlers);

	$report->($handlers) if ($report);

	my $sg = Scope::Guard->new(sub { Autobox::leavescope() });
	$^H{$sg} = $sg;

	Autobox::enterscope();
}

sub unimport {
    $^H &= ~0x20000;
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

    # can(), isa() and VERSION() work as expected

	if ("Hello, World"->can('foo')) ...
	if (3.1415927->isa('Number')) ...
	if ([ ... ]->VERSION() > 0.01) ...

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
		DEFAULT => ...,		    # can take any of the 4 types above
		UNDEF   => ...,		    # can take any of the 4 types above
		REPORT  => ...;		    # boolean or coderef

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

In addition to the SCALAR, ARRAY, HASH, CODE and DEFAULT fields above,
there are two additional fields: UNDEF and REPORT.

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

=head2 REPORT

REPORT exposes the current handlers by means of a callback, or a
static reporting function.

This can be useful if one wishes to see the computed bindings
in 'longhand'.

Reporting is ignored if the value corresponding to the REPORT key is false.

If the value is a CODE ref, then this sub is called with a reference to
the HASH containing the computed handlers for the current scope.

Finally, if REPORT is true but not a CODE ref, the handlers are dumped
to STDERR.

Thus:

    use autobox REPORT => 1, ...

or

    use autobox REPORT => sub { ... }, ...

or

    sub my_callback ($) {
	my $hashref = shift;
	...
    }

    use autobox REPORT => \&my_callback, ...

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

Although C<isa> and C<can> are "overloaded" for autoboxed values, the C<VERSION> method isn't.
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

1.00

=head1 AUTHOR
    
chocolateboy: <chocolate.boy@email.com>

=head1 SEE ALSO

L<autobox::Core>, L<Perl6::Contexts>, L<Scalar::Properties>, L<Set::Array>, L<String::Ruby>

=cut
