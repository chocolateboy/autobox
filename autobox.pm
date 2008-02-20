package autobox;

use 5.008;
use strict;
use warnings;

use Carp qw(confess);
use XSLoader;
use Scalar::Util qw(blessed);
use Scope::Guard;
use Storable ();

our $VERSION = '2.10';

XSLoader::load 'autobox', $VERSION;

############################################# PRIVATE ###############################################

my $SEQ   = 0;
my $CACHE = {};    # hold a reference to the bindings hashes

# create a shim class - actual methods are implemented by the classes in its @ISA
sub _generate_class($) {
    my $type = lc shift;
    ++$SEQ;
    return "autobox::$type\::<$SEQ>";
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

# default method called when the DEBUG option is supplied with a true value
# prints the assigned bindings for the current scope along with a list of classes in their @ISA
sub _debug ($) {
    my $bindings = annotate(shift);
    require Data::Dumper;
    no warnings qw(once);
    local ($|, $Data::Dumper::Indent, $Data::Dumper::Terse, $Data::Dumper::Sortkeys) = (1, 1, 1, 1);
    print STDERR Data::Dumper::Dumper($bindings), $/;
}

# return true if $ref ISA $class - works with non-references, unblessed references and objects
sub _isa($$) {
    my ($ref, $class) = @_;
    return blessed($ref) ? $ref->isa($class) : ref($ref) eq $class;
}

# get the @ISA for the specified class
sub _get_isa($) {
    my $class = shift;
    my $isa   = do {
        no strict 'refs';
        *{"$class\::ISA"}{ARRAY};
    };
    return wantarray ? @$isa : $isa;
}

# install a new set of bindings for the current scope
sub _register ($) {
    my $bindings = shift;

    # don't bother if there's no change
    return if ($^{autobox} && (Storable::freeze($^{autobox}) eq Storable::freeze($bindings)));

    # As an optimization, the synthetic class is replaced with the actual class if there's
    # only one. This speeds up method lookup as the method can (often) be found directly in the stash
    # rather than in the ISA hierarchy with its attendant AUTOLOAD-related overhead

    my $optimize = sub {
        for my $key (keys %$bindings) {
            my $class = $bindings->{$key};
            my @isa   = _get_isa($class);
            if (@isa == 1) {
                $class = $isa[0];
                $bindings->{$key} = $class;
                _universalize($class);
            }
        }
    };

    my $sg = Scope::Guard->new($optimize);

    $^H{autobox} = $bindings;
    # we can safely clobber (i.e. trigger) the previous optimizer now we've assigned
    # a new binding for this scope
    $^H{autobox_optimize} = $sg;
    $CACHE->{$bindings} = $bindings; # keep the $bindings hash alive
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

# This undocumented method takes a bindings hash and appends a list of superclasses to its values
# It's used by the test suite (hence the public-looking name) but is otherwise private
sub annotate($) {
    my $hash = { %{ shift() } };
    for my $key (keys %$hash) {
        my $value = $hash->{$key};
        $hash->{$key} = join(', ', _get_isa($value));
    }
    return $hash;
}

# enable some flavour of autoboxing in the current scope
sub import {
    my ($class, %args) = @_;
    my $defaults = $class->defaults();
    my $debug    = delete $args{DEBUG};

    # Don't do this until DEBUG has been deleted
    %args = %$defaults unless (%args);

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

    _register($bindings);

    # fill in defaults for unhandled cases; namespace expansion is handled below
    if (defined $default) {
        for my $key (keys %$defaults) {
            next if (exists $args{$key});    # don't supply a default if the binding is already explicitly defined
            next if ($key eq 'UNDEF');       # UNDEF must be autoboxed explicitly - DEFAULT doesn't include it
            next if ($key eq 'DEFAULT');     # already merged into $default above

            $args{$key} = $default;
        }
    }

    # sanity check %args, expand the namespace prefixes into class names,
    # and copy defined values to the $bindings hash

    for my $key (keys %args) {
        confess("unrecognised option: '", (defined $key ? $key : '<undef>'), "'") unless (exists $defaults->{$key});

        my $value = $args{$key};

        next unless (defined $value);

        my $outer_class = exists($bindings->{$key}) ? $bindings->{$key} : undef; # don't autovivify
        my ($synthetic_class, $new_synthetic_class);

        if ($new_scope || not($outer_class)) {
            # new synthetic class - either a new scope, or a new type in an existing scope
            $synthetic_class = _generate_class($key);
            $new_synthetic_class = 1;
        } else {
            $synthetic_class = $outer_class;
            $new_synthetic_class = 0;
        }

        my $synthetic_class_isa = _get_isa($synthetic_class);

        # if this is a new nested scope, merge superclasses for this type from the outer scope
        if ($new_scope && $outer_class) {
            my $outer_isa = _get_isa($outer_class);

            for my $merge_class (@$outer_isa) {
                push(@$synthetic_class_isa, $merge_class)
                    unless (grep { $_ eq $merge_class } @$synthetic_class_isa); # no dups
            }
        }

        # we can't use UNIVERSAL::isa to test if $value is an array ref;
        # if the value is 'ARRAY', and that package exists, then UNIVERSAL::isa('ARRAY', 'ARRAY') is true!

        $value = [ $value ] unless (_isa($value, 'ARRAY'));

        for my $user_class (@$value) {
            # squashed bug: if $user_class is a default namespace that was passed in an array ref,
            # then that array ref may have been assigned as the default for multiple types
            #
            # mutating it (e.g. $user_class = "$user_class::$key") mutates it for all
            # the types that have been assigned this default (due to the aliasing semantics of foreach). which
            # means defaulted types all inherit MyNamespace::CODE (or whatever comes first)
            #
            # creating a copy of $user_class and appending to that rather than mutating the original fixes this
            # 
            # see tests 27 and 28 in merge.t
            my $expanded = ($user_class =~ /::$/) ? "$user_class$key" : $user_class; # handle namespace expansion

            push(@$synthetic_class_isa, $expanded)
                unless (grep { $_ eq $expanded } @$synthetic_class_isa); # no dups
        }

        if ($new_synthetic_class) {
            _universalize($synthetic_class);
            $bindings->{$key} = $synthetic_class;
        }
    }

    # This turns on autoboxing i.e. the method call checker sets a flag on the method call op
    # and replaces its default handler with the autobox implementation.
    #
    # It needs to be set unconditionally because it may have been unset in unimport
    $^H |= 0x120000; # set HINT_LOCALIZE_HH + an unused bit to work around a %^H bug

    if ($debug) {
        $debug = \&_debug unless (_isa($debug, 'CODE'));
        $debug->($bindings);
    }

    return unless ($new_scope);

    # This sub is called when the current scope's %^H is destroyed i.e. at the end of the compilation of the scope
    #
    # Autobox::enterscope splices in the autobox method call checker and method call op if they're not already
    # active
    #
    # Autobox::leavescope performs the neccessary housekeeping to ensure that the default checker and op are restored
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
# (autobox_scope); we also need a new bindings hash: if one or more bindings is being disabled, we need
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

    my $new_bindings = { %{$^H{autobox}} }; # clone the current bindings hash

    @args = keys(%$defaults) unless (@args);

    for my $arg (@args) {
        confess("unrecognised option: '", (defined $arg ? $arg : '<undef>'), "'") unless (exists $defaults->{$arg});
        delete $new_bindings->{$arg};
    }

    # unset HINT_LOCALIZE_HH + the additional bit if there are no more bindings in this scope
    $^H &= ~0x120000 unless (%$new_bindings);
    _register($new_bindings);
}

1;
