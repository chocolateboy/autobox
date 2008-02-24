package autobox;

use 5.008;

use strict;
use warnings;

use Carp;
use XSLoader;
use Scalar::Util;
use Scope::Guard;
use Storable;

our $VERSION = '2.23';

XSLoader::load 'autobox', $VERSION;

############################################# PRIVATE ###############################################

my $SEQ            = 0;  # unique identifier for synthetic classes
my $BINDINGS_CACHE = {}; # hold a reference to the bindings hashes
my $CLASS_CACHE    = {}; # reuse the same synthetic class if the type/superclasses are the same

# create a shim class - actual methods are implemented by the classes in its @ISA
#
# as an optimization, or at least a courtesy, return the previously-generated class
# if we've seen the same (canonicalized) type/isa combination before

sub _generate_class($@) {
    my ($type, $isa) = @_;

    # As an optimization, simply return the class if there's only one.
    # This speeds up method lookup as the method can (often) be found directly in the stash
    # rather than in the ISA hierarchy with its attendant AUTOLOAD-related overhead

    if (@$isa == 1) {
        my $class = $isa->[0];
        _universalize($class); # nop if it's already been universalized
        return $class;
    }

    my $key = Storable::freeze([ $type, sort(@$isa) ]); # sort() - canonicalize the @isa

    return $CLASS_CACHE->{$key} ||= do {
        my $class = sprintf('autobox::shim::<%d>', ++$SEQ);
        my $synthetic_class_isa = _get_isa($class); # i.e. autovivify

        @$synthetic_class_isa = @$isa;
        _universalize($class);
        $class;
    };
}

# make can() and isa() work as expected for autoboxed values by calling the method on their associated class
sub _universalize ($) {
    my $class = shift;
    return unless (defined $class);
    {
        no strict 'refs';
        *{"$class\::can"} = sub { shift; UNIVERSAL::can($class, @_) } unless (*{"$class\::can"}{CODE});
        *{"$class\::isa"} = sub { shift; UNIVERSAL::isa($class, @_) } unless (*{"$class\::isa"}{CODE});
    }
}

# pretty-print the bindings hash by showing its values as the inherited classes rather than the synthetic class
sub _annotate($) {
    my $hash = { %{ shift() } };

    # reverse() turns a hash that maps a type/isa signature to a class name into a hash that maps
    # a class name into a boolean
    my %synthetic = reverse(%$CLASS_CACHE);

    for my $key (keys %$hash) {
        my $value = $hash->{$key};
        $hash->{$key} = join(', ', _get_isa($value)) if ($synthetic{$value});
    }

    return $hash;
}

# default method called when the DEBUG option is supplied with a true value
# prints the assigned bindings for the current scope

sub _debug ($) {
    my $bindings = shift;
    require Data::Dumper;
    no warnings qw(once);
    local ($|, $Data::Dumper::Indent, $Data::Dumper::Terse, $Data::Dumper::Sortkeys) = (1, 1, 1, 1);
    print STDERR Data::Dumper::Dumper($bindings), $/;
}

# return true if $ref ISA $class - works with non-references, unblessed references and objects
sub _isa($$) {
    my ($ref, $class) = @_;
    return Scalar::Util::blessed($ref) ? $ref->isa($class) : ref($ref) eq $class;
}

# get/autovivify the @ISA for the specified class
sub _get_isa($) {
    my $class = shift;
    my $isa   = do {
        no strict 'refs';
        *{"$class\::ISA"}{ARRAY};
    };
    return wantarray ? @$isa : $isa;
}

# install a new set of bindings for the current scope
#
# XXX this could be refined to reuse the same hashref if its contents have already been seen,
# but that requires each (frozen) hash to be cached; at best, it may not be much of a win, and at
# worst it will increase bloat

sub _register ($) {
    my $bindings = shift;
    $^H{autobox} = $bindings;
    $BINDINGS_CACHE->{$bindings} = $bindings; # keep the $bindings hash alive
}

############################################# PUBLIC (Methods) ###############################################

# allow subclasses to provide new defaults and/or allow a wider or narrower range of types to be autoboxed.
#
# the full list of supported types is:
#
#     REF SCALAR LVALUE ARRAY HASH CODE GLOB FORMAT IO UNKNOWN

sub defaults {
    my $class = shift;
    return {
        SCALAR  => 'SCALAR',
        ARRAY   => 'ARRAY',
        HASH    => 'HASH',
        CODE    => 'CODE',
        UNDEF   => undef,
        DEFAULT => undef
    };
}

# enable some flavour of autoboxing in the current scope
sub import {
    my ($class, %args) = @_;
    my $defaults = $class->defaults();
    my $debug    = delete $args{DEBUG};

    # Don't do this until DEBUG has been deleted
    unless (%args) {
        for my $key (keys %$defaults) {
            $args{$key} = $defaults->{$key} if ($defaults->{$key});
        }
    }

    my $default = exists $args{DEFAULT} ? delete $args{DEFAULT} : $defaults->{DEFAULT};
    my $bindings; # custom typemap

    # this is %^H as an integer - it changes as scopes are entered/left
    # we don't need to stack/unstack it in %^H as %^H itself takes care of that
    my $scope = Autobox::scope();

    my $new_scope; # is this a new (top-level or nested) scope?

    if ($^H{autobox_scope} && ($^H{autobox_scope} == $scope)) {
        $new_scope = 0;
    } else {
        $^H{autobox_scope} = $scope;
        $new_scope = 1;
    }

    # clone the bindings hash if available
    #
    # we may be assigning to it, and we don't want to contaminate outer/previous bindings
    # with nested/new bindings
    #
    # as of 5.10, references in %^H get stringified at runtime, but we don't need them then

    $bindings = $^H{autobox} ? { %{ $^H{autobox} } } : {};

    # fill in defaults for unhandled cases; namespace expansion is handled below
    if (defined $default) {
        for my $key (keys %$defaults) {
            next if (exists $args{$key});    # don't supply a default if the binding is explicitly defined
            next if ($key eq 'UNDEF');       # UNDEF must be autoboxed explicitly - DEFAULT doesn't include it
            next if ($key eq 'DEFAULT');     # already merged into $default above

            $args{$key} = $default;
        }
    }

    # sanity check %args, expand the namespace prefixes into class names,
    # and copy defined values to the $bindings hash

    for my $type (keys %args) {
        Carp::confess("unrecognized option: '", (defined $type ? $type : '<undef>'), "'")
            unless (exists $defaults->{$type});

        my $value = $args{$type};

        next unless ($value);

        my @isa = ();
        my %synthetic = reverse (%$CLASS_CACHE); # synthetic class name => bool - see _annotate
       
        if (exists($bindings->{$type})) { # don't autovivify
            my $class = $bindings->{$type};
            @isa = $synthetic{$class} ? _get_isa($class) : ($class);
        }

        # we can't use UNIVERSAL::isa to test if $value is an array ref;
        # if the value is 'ARRAY', and that package exists, then UNIVERSAL::isa('ARRAY', 'ARRAY') is true!

        $value = [ $value ] unless (_isa($value, 'ARRAY'));

        for my $class (@$value) {
            # squashed bug: if $class is a default namespace that was passed in an array ref,
            # then that array ref may have been assigned (above) as the default for multiple types
            #
            # mutating it (e.g. $class = "$class$type") mutates it for all
            # the types that default to this namespace (due to the aliasing semantics of foreach). which
            # means defaulted types all inherit MyNamespace::CODE (or whatever comes first)
            #
            # creating a copy of $class and appending to that rather than mutating the original fixes this
            # 
            # see tests 27 and 28 in merge.t
            my $expanded = ($class =~ /::$/) ? "$class$type" : $class; # handle namespace expansion

            push (@isa, $expanded) unless (grep { $_ eq $expanded } @isa); # no dups
        }

        # associate the synthetic class with the specified type
        $bindings->{$type} = _generate_class($type, \@isa);
    }

    # This turns on autoboxing i.e. the method call checker sets a flag on the method call op
    # and replaces its default handler with the autobox implementation.
    #
    # It needs to be set unconditionally because it may have been unset in unimport
    $^H |= 0x120000; # set HINT_LOCALIZE_HH + an unused bit to work around a %^H bug

    if ($debug) {
        $debug = \&_debug unless (_isa($debug, 'CODE'));
        $debug->(_annotate($bindings));
    }

    # install the specified bindings in the current scope
    _register($bindings);

    return unless ($new_scope);

    # This sub is called when the current scope's %^H is destroyed i.e. at the end of the compilation of the scope
    #
    # Autobox::enterscope splices in the autobox method call checker and method call op if they're not already
    # active
    #
    # Autobox::leavescope performs the necessary housekeeping to ensure that the default checker and op are restored
    # when autobox is no longer in scope

    my $leave_scope = sub {
        Autobox::leavescope();
    };

    my $sg = Scope::Guard->new($leave_scope);
    $^H{autobox_leavescope} = $sg;

    Autobox::enterscope();
}

# delete one or more bindings; if none remain, turn off the autoboxing flag
#
# note: the housekeeping data structures are not deleted: import still needs to know if we're in the same scope
# (autobox_scope) &c.; we also need a new bindings hash: if one or more bindings are being disabled, we need
# to create a new hash (a clone of the current hash) so that the previous hash (if any) is not contaminated
# by new deletions(s)
#
#   use autobox;
#
#       "foo"->bar;
#
#   no autobox; # don't clobber the default bindings for "foo"->bar

sub unimport {
    my ($class, @args) = @_;
    my $defaults = $class->defaults();

    # the only situation in which there is no bindings hash is if this is a "no autobox"
    # that precedes any "use autobox", in which case we don't need to turn autoboxing off as it's
    # not yet been turned on
    return unless ($^H{autobox});

    my $bindings = { %{$^H{autobox}} }; # clone the current bindings hash

    @args = keys(%$defaults) unless (@args);

    for my $arg (@args) {
        Carp::confess("unrecognized option: '", (defined $arg ? $arg : '<undef>'), "'")
            unless (exists $defaults->{$arg});
        delete $bindings->{$arg};
    }

    # unset HINT_LOCALIZE_HH + the additional bit if there are no more bindings in this scope
    $^H &= ~0x120000 unless (%$bindings);
    _register($bindings);
}

1;
