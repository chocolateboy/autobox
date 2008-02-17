package autobox;

use 5.008;
use strict;
use warnings;

use Carp qw(confess);
use XSLoader;
use Scalar::Util qw(blessed);
use Scope::Guard;

our $VERSION = '2.02';

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
    local ($|, $Data::Dumper::Indent, $Data::Dumper::Terse) = (1, 1, 1);
    print STDERR Data::Dumper::Dumper($bindings), $/;
}

# return true if $ref ISA class - works with non-references, unblessed references and objects
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
        $hash->{$key} .= ' (' . join(', ', _get_isa($value)) . ')';
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
    my $bindings;    # custom typemap
    my $augment = 0; # is this call augmenting the current scope's bindings?

    # this is %^H as an integer - it changes as scopes are entered/left
    # we don't need to stack/unstack it in %^H as %^H itself takes care of that
    my $scope = Autobox::scope();

    # if we're calling "use autobox" again in the same scope (i.e. augmenting the bindings)
    # a "use autobox ..." following an initial "no autobox" would be an apparent augment, even though the bindings
    # hash has not been initialized, so don't assume "same scope" means it's already there
    if ($^H{autobox} && $^H{autobox_scope} && (($^H & 0x120000) == 0x120000) && ($^H{autobox_scope} == $scope)) {
        $augment  = 1;
        $bindings = $^H{autobox};    # as of 5.10 this gets stringified at runtime, but we don't need it then
    } else {
        # clone the outer bindings hash if available
        # we may be assigning to it, and we don't want to contaminate the outer hash with nested bindings
        $bindings = $^H{autobox} ? { %{ $^H{autobox} } } : {};
    }

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
        my $new_synthetic_class = 0;
        my $synthetic_class;

        if ($augment && $outer_class) {
            $synthetic_class = $outer_class;
        } else { # new synthesized class - either a new scope, or a new type in an existing scope
            $synthetic_class     = _generate_class($key);
            $new_synthetic_class = 1;
        }

        my $synthetic_class_isa = _get_isa($synthetic_class);

        # if this is a new inner scope, merge superclasses for this type from the outer scope
        if (not($augment) && $outer_class) {
            my $outer_isa = _get_isa($outer_class);

            for my $merge_class (@$outer_isa) {
                push(@$synthetic_class_isa, $merge_class)
                  unless (grep { $_ eq $merge_class } @$synthetic_class_isa);    # no dups
            }
        }

        # we can't use UNIVERSAL::isa to test if $value is an array ref
        # if the value is 'ARRAY', and that package exists, then UNIVERSAL::isa('ARRAY', 'ARRAY') is true!

        $value = [ $value ] unless (_isa($value, 'ARRAY'));

        for my $user_class (@$value) {
            $user_class = "$user_class$key" if ($user_class =~ /::$/);           # handle namespace expansion
            push(@$synthetic_class_isa, $user_class)
              unless (grep { $_ eq $user_class } @$synthetic_class_isa);         # no dups
        }

        if ($new_synthetic_class) {
	    _universalize($synthetic_class);
            $bindings->{$key} = $synthetic_class;
        }
    }

    unless ($augment) {
        $^H |= 0x120000; # set HINT_LOCALIZE_HH + an unused bit to work around a %^H bug
        $^H{autobox}        = $bindings;
        $^H{autobox_scope}  = $scope;
        $CACHE->{$bindings} = $bindings;                                         # keep the $bindings hash alive
    }

    if ($debug) {
        $debug = \&_debug unless (ref($debug) eq 'CODE');
        $debug->($bindings);
    }

    return if ($augment);

    # This sub is called when the current scope's %^H is destroyed i.e. at the end of the compilation of the scope
    #
    # Autobox::enterscope splices in the autobox method call checker and method call op if they're not already
    # enabled
    #
    # Autobox::leavescope performs the neccessary housekeeping to ensure that the default checker and op are restored
    # when autobox is no longer in scope
    #
    # As an optimization, we replace the synthetic class with the actual class for a type if there's
    # only one. This speeds up method lookup as the method can (often) be found directly in the stash
    # rather than in the ISA hierarchy with its attendant AUTOLOAD-related overhead

    my $leave_scope = sub {
        for my $key (keys %$bindings) {
            my $class = $bindings->{$key};
            my @isa   = _get_isa($class);
            if (@isa == 1) {
		$class = $isa[0];
                $bindings->{$key} = $class;
		_universalize($class);
            }
        }
        Autobox::leavescope();
    };

    my $sg = Scope::Guard->new($leave_scope);
    $^H{$sg} = $sg;

    Autobox::enterscope();
}

sub unimport {
    my ($class, @args) = @_;
    my $defaults = $class->defaults();

    return unless ($^H{autobox});

    if (@args) {
        for my $arg (@args) {
            confess("unrecognised option: '", (defined $arg ? $arg : ''), "'") unless (exists $defaults->{$arg});
            delete $^H{autobox}->{$arg};
        }
    } else {

        # a nested "no autobox" doesn't disable autoboxing for the scope; it just clears the $bindings hash
        for my $key (keys %{ $^H{autobox} }) {
            delete $^H{autobox}->{$key};    # don't delete the hash - augment may still expect it to be there
        }
    }
}

1;
