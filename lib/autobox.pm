package autobox;

use strict;
use warnings;

$| = 1;

our $VERSION = 0.01;

our $hint_bits = 0x20000; # HINT_LOCALIZE_HH

our $types = {
    map { $_ => $_ }
    # qw(REF SCALAR LVALUE ARRAY HASH CODE GLOB FORMAT IO UNKNOWN)
    qw(SCALAR ARRAY HASH CODE) # only support the core types
};

sub report {
    my $handlers = shift;
    require Data::Dumper;
    local $Data::Dumper::Indent = $Data::Dumper::Terse = 1;
    print STDERR Data::Dumper::Dumper($handlers), $/;
}

our %cache = ();

sub is_namespace ($) { $_[0] eq '' or ($_[0] =~ /::$/) }

sub import {
    shift;
    my $handlers = { };
    my $report;

    if (scalar @_) {
	my %args = @_;
	my %seen = %$types;
	my $default = exists $args{DEFAULT} ? delete $args{DEFAULT} : '';
       
	if ($report = delete $args{REPORT}) { # REPORT => 1 : print to STDERR
	    $report = \&report unless (ref $report eq 'CODE');
	}
	
	for my $key (keys %args) {
	    die ("autobox: unrecognised type: '", (defined $key ? $key : ''), "'") 
		unless ($types->{$key});

	    delete $seen{$key}; # delete before iterating

	    my $value = $args{$key};

	    next unless (defined $value);

	    $handlers->{$key} = is_namespace($value) ? "$value$key" : $value;
	}

	if (defined $default) {
	    for my $key (keys %seen) {
		$handlers->{$key} = is_namespace($default) ? "$default$key" : $default;
	    }
	}
    } else {
	$handlers = $types;
    }

    my $key = sprintf '0x%x', int ($handlers);
    
    $cache{$key} = $handlers;

    $^H |= $hint_bits;
    $^H{AUTOBOX} = $key;

    # $report->($key, $handlers) if ($report);
    $report->($handlers) if ($report);
}

sub unimport {
    shift;
    $^H &= ~$hint_bits;
    delete $^H{AUTOBOX};
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
	my $ton = $range->[0]->mul(10);

    # floats...

	my $error = 3.1415927->minus(22/7)->abs();

    # strings...

	my $uri = "http://www.%s.com/foo.pl?arg=%s"->f($domain, $arg->escape());
	my $message = 'autobox'->google();

	my $word = 'rubicund';
	my $definition = $word->lookup_on_dictionary_dot_com();

	my $greeting = "Hello, World"->upper(); # "HELLO, WORLD"

	$greeting->to_lower(); # greeting is now "hello, world"
	$greeting->for_each(\&character_handler);

    # ARRAY refs...

	my $schwartzian = [ @_ ]->map(...)->sort(...)->map(...);

    # HASH refs

	my $hash_iterator = sub { my ($key, $value) = @_; ... };

	{ alpha => 'beta', gamma => 'vlissides' }->for_each($hash_iterator);

    # CODE refs

	my $plus_five = (\&add)->curry()->(5);
	my $minus_three = sub { $_[0] - $_[1] }->reverse->curry->(3);

	$plus_five->($hashref->size());
	$minus_three->([ 1, 8, 3, 3, 2, 9 ]->standard_deviation());

=head1 DESCRIPTION

The autobox pragma equips Perl's core datatypes with the capabilities of
first-class objects. This enables methods to be called on ARRAY refs,
HASH refs, CODE refs and raw SCALARs in exactly the same manner as blessed
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

autoboxing can be turned off entirely by using the C<no> syntax:

    {
	use autobox;
	...
	no autobox;
	...
    }

- as well as by specifying a sole default value of undef (see below):

    use autobox DEFAULT => undef;

Autoboxing is not performed for bare words i.e. 

    my $foo = Foo->new();

and:

    my $foo = new Foo;

perform as expected.

The classes into which the core types are boxed are fully configurable.
By default, a method invoked on a non-object value is assumed to be
defined in a package whose name corresponds to the ref() type of that
value - with the exception of non-reference SCALAR types (i.e. strings,
integers, floats) which are implicitly 'promoted' to the SCALAR class.

Thus a vanilla

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

    SCALAR::upper("Hello, World")

while:

    [ 1 .. 10 ]->for_each(sub { ... })

resolves to:

    ARRAY::for_each([ 1 .. 10 ], sub { ... })

A mapping from the ref type to the user-defined type can be specified
by passing a list of key/value bindings to the C<use autobox> statement.

The following example shows the range of valid values:

    use autobox SCALAR  => 'MyScalar'	    # package name
		ARRAY   => 'MyNamespace::', # package prefix (ending in '::')
		HASH    => '',		    # use the default i.e. HASH 
		CODE    => undef,	    # don't autobox this type
		DEFAULT => ...,		    # can take any of the 4 types above
		REPORT  => ...;		    # boolean or coderef

SCALAR, ARRAY, HASH, CODE and DEFAULT can take four different types of value:

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
to which the name of the default handler for this class will be appended:

Thus:

    use autobox ARRAY => 'Prelude::';

binds ARRAY types to the Prelude::ARRAY package.

As with the package name form, specifying a default namespace e.g.

    use autobox SCALAR	=> 'MyScalar',
		DEFAULT => 'MyNamespace::';

binds MyNamespace::ARRAY, MyNamespace::HASH &c. to each unhandled
builtin type.

=item *

An empty string: this is shorthand for the default (builtin) type name. e.g.

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
there is an additional diagnostic field, REPORT, which exposes the
current handlers by means of a callback, or a static reporting function.

This can be useful if one wishes to see the computed class bindings
in 'longhand'.

Reporting is ignored if the value coresponding to the REPORT key is false.

If the value is a CODE ref, then this sub is called with a reference to
the HASH containing the computed handlers for the current scope.

Finally, if REPORT is true but not a CODE ref, the handlers are dumped
to STDERR.

Thus:

    use autobox REPORT => 1, ...

# or

    use autobox REPORT => sub { ... }, ...

# or

    sub my_callback ($$) {
	my ($key, $hashref) = @_;
	...
    }

    use autobox REPORT => \&my_callback, ...

=head1 CAVEATS

Due to Perl's precedence rules some autoboxed literals may need to be
parenthesized:

For instance, while this works:

    my $curried = $sub { ... }->curry();

this doesn't:

    my $curried = \&foo->curry();

The solution is to wrap the reference in parentheses:

    my $curried = (\&foo)->curry();

The same applies for signed integer and float literals:

    # this doesn't work
    my $range = -10->to(10);

    # this does
    my $range = (-10)->to(10);

=head1 REQUIREMENTS

This pragma requires a patch against perl-5.8.1-RC4. It is supplied
in the patch directory of the distribution.

Core modules for SCALAR, ARRAY, HASH and CODE (i.e. a Perl Standard
Prelude) are not provided.

=head1 VERSION

    0.01

=head1 AUTHOR
    
    chocolateboy: <chocolate.boy@email.com>

SEE ALSO

    Java 1.5 (Tiger), C#, Ruby

=cut
