package autobox;

use 5.008;

use strict;
use warnings;

use Carp;
use XSLoader;
use Scalar::Util;
use Scope::Guard;
use Storable;

our $VERSION = '2.52';

XSLoader::load 'autobox', $VERSION;

############################################# PRIVATE ###############################################

my $SEQ            = 0;  # unique identifier for synthetic classes
my $BINDINGS_CACHE = {}; # hold a reference to the bindings hashes
my $CLASS_CACHE    = {}; # reuse the same synthetic class if the type/superclasses are the same

# create a shim class - actual methods are implemented by the classes in its @ISA
#
# as an optimization, return the previously-generated class
# if we've seen the same (canonicalized) type/isa combination before

sub _generate_class($$) {
    my ($type, $isa) = @_;
    my @isa;  # List::MoreUtils::uniq would go down a treat here, but let's try to keep this light on dependencies
    my %seen; # we can't just map into a hash as we need to preserve the order

    for my $superclass (@$isa) {
        next if ($seen{$superclass});
        push @isa, $superclass;
        $seen{$superclass} = 1;
    }

    # As an optimization, simply return the class if there's only one.
    # This speeds up method lookup as the method can (often) be found directly in the stash
    # rather than in the ISA hierarchy with its attendant AUTOLOAD-related overhead
    if (@isa == 1) {
        my $class = $isa[0];
        _universalize($class); # nop if it's already been universalized
        return $class;
    }

    # don't sort() the @isa as this incorrectly gives "use autobox SCALAR => [ qw(Foo Bar) ]" the same
    # synthetic class as "use autobox SCALAR => [ qw(Bar Foo) ]" - see isa.t
    my $key = Storable::freeze([ $type, @isa ]);

    return $CLASS_CACHE->{$key} ||= do {
        my $class = sprintf('autobox::shim::<%d>', ++$SEQ);
        my $synthetic_class_isa = _get_isa($class); # i.e. autovivify

        @$synthetic_class_isa = @isa;
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

    delete $hash->{_children}; # hide the housekeeping key

    # reverse() turns a hash that maps a type/isa signature to a class name into a hash that maps
    # a class name into a boolean
    my %synthetic = reverse(%$CLASS_CACHE);

    for my $key (keys %$hash) {
        my $value = $hash->{$key};
        $hash->{$key} = $synthetic{$value} ? [ _get_isa($value) ] : [ $value ];
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

sub _install ($) {
    my $bindings = shift;
    $^H{autobox} = $bindings;
    $BINDINGS_CACHE->{$bindings} = $bindings; # keep the $bindings hash alive
}

# autobox.xs looks up the most specific type for each invocant e.g. INTEGER, FLOAT, STRING
# these then need to be assigned bindings *if any of their supertypes have bindings*
# this ensures that calling a method on e.g. a FLOAT delegates to NUMBER (if defined) then SCALAR
# (if defined). This sub adds those implicit bindings

sub _inherit($$@) {
    my ($hash, $type, $supertype) = @_;

    if (exists $hash->{$supertype}) { # don't autovivify
        my $superclass = $hash->{$supertype};

        if (exists $hash->{$type}) { # don't autovivify
            $hash->{$type} = [ $hash->{$type} ] unless (_isa($hash->{$type}, 'ARRAY'));
        } else {
            $hash->{$type} = []; # autogenerate
            # log the autogenerated subtypes so that we can remove them from the bindings 
            # when the supertype is deleted
            $hash->{_children}->{$supertype} ||= [];
            push @{$hash->{_children}->{$supertype}}, $type;
        }

        push @{$hash->{$type}}, (_isa($superclass, 'ARRAY') ? @$superclass : $superclass);
    }
}

############################################# PUBLIC (Methods) ###############################################

# allow subclasses to provide new defaults and/or allow a wider or narrower range of types to be autoboxed.
#
# the full list of supported types is:
#
#     ARRAY BIND CODE FLOAT FORMAT GLOB HASH INTEGER IO LVALUE REF STRING UNDEF UNKNOWN VSTRING
#
# virtual types exist to assign classes to their subtypes and don't exist as types in their
# own right

sub defaults {
    my $class = shift;
    return {
        ARRAY   => 'ARRAY',
        CODE    => 'CODE',
        DEFAULT => undef,
        FLOAT   => undef,
        HASH    => 'HASH',
        INTEGER => undef,
        NUMBER  => undef,    # virtual
        SCALAR  => 'SCALAR', # virtual
        STRING  => undef,
        UNDEF   => undef
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
            next unless ($defaults->{$key}); # don't supply a default unless defaults() marks this type as defaultable
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

        # perform namespace expansion
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

            push (@isa, $expanded); # dups are removed in _generate_class
        }

        $bindings->{$type} = [ @isa ]; # assign the namespace-expanded @isa to our $bindings hash
    }

    # thread together the class hierarchy for SCALAR subtypes; superclasses are only
    # appended to the subtype's isa if bindings for the superclass are defined
    # this must be done *after* namespace expansion and *before* _generate_class removes dups
    # and collapses the @isa array ref into a class name
    _inherit($bindings, 'NUMBER', 'SCALAR'); # the order is important
    _inherit($bindings, 'STRING', 'SCALAR');
    _inherit($bindings, 'INTEGER', 'NUMBER');
    _inherit($bindings, 'FLOAT', 'NUMBER');

    # finally: replace each array ref of superclasses with the name of the generated class.
    # if there's only one superclass in the type's @ISA (e.g. SCALAR => 'MyScalar') then
    # that class is used; otherwise a shim class whose @ISA contains the two or more classes
    # is created 
    for my $type (keys %$bindings) {
        next if ($type eq '_children');

        my $value = $bindings->{$type};

        # the value may be a string inherited from the previous/outer scope
        # there's no harm in resubmitting it to _generate_class: it
        # will simply return the class name unchanged (from its cache)
        
        $value = [ $value ] unless (_isa($value, 'ARRAY'));

        # delete empty arrays e.g. use autobox SCALAR => []
        if (@$value == 0) {
            delete $bindings->{$type};
        } else {
            # associate the synthetic/single class with the specified type
            $bindings->{$type} = _generate_class($type, $value); 
        }
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
    _install($bindings);

    # this is %^H as an integer - it changes as scopes are entered/exited
    # we don't need to stack/unstack it in %^H as %^H itself takes care of that
    # note: we need to call this *after* %^H is referenced (and possibly created) above
    my $scope = autobox::scope();
    my $old_scope = exists($^H{autobox_scope})? $^H{autobox_scope} : 0;
    my $new_scope; # is this a new (top-level or nested) scope?

    if ($scope == $old_scope) {
        $new_scope = 0;
    } else {
        $^H{autobox_scope} = $scope;
        $new_scope = 1;
    }

    # warn "OLD ($old_scope) => NEW ($scope): $new_scope ", join(':', (caller(1))[0 .. 2]), $/;

    return unless ($new_scope);

    # This sub is called when this scope's $^H{autobox_leavescope} is deleted, usually when
    # %^H is destroyed at the end of the scope, but possibly directly in unimport()
    #
    # autobox::enterscope splices in the autobox method call checker and method call op
    # if they're not already active
    #
    # autobox::leavescope performs the necessary housekeeping to ensure that the default
    # checker and op are restored when autobox is no longer in scope

    my $leave_scope = sub {
        autobox::leavescope();
    };

    my $guard = Scope::Guard->new($leave_scope);
    $^H{autobox_leavescope} = $guard;

    autobox::enterscope();
}

# delete one or more bindings; if none remain, disable autobox in the current scope
#
# note: if bindings remain, we need to create a new hash (initially a clone of the current
# hash) so that the previous hash (if any) is not contaminated by new deletions(s)
#
#   use autobox;
#
#       "foo"->bar;
#
#   no autobox qw(SCALAR); # don't clobber the default bindings for "foo"->bar
#
# however, if there are no more bindings we can remove all traces of autobox from the
# current scope.

sub unimport {
    my ($class, @args) = @_;
    my $defaults = $class->defaults();

    # the only situation in which there is no bindings hash is if this is a "no autobox"
    # that precedes any "use autobox", in which case we don't need to turn autoboxing off as it's
    # not yet been turned on
    return unless ($^H{autobox});

    my $bindings = { %{$^H{autobox}} }; # clone the current bindings hash
    my $children = exists $bindings->{_children} ? $bindings->{_children} : {};

    @args = keys(%$defaults) unless (@args);

    # cheap recursion; the real thing doesn't work because each frame creates its own copy of
    # $bindings
    while (@args) {
        my $type = shift(@args);

        Carp::confess("unrecognized option: '", (defined $type ? $type : '<undef>'), "'")
            unless (exists $defaults->{$type});

        # delete the children that were created automatically (i.e. not bound explicitly)
        # for this type 
        if (exists $children->{$type}) { # don't autovivify
            push @args, @{$children->{$type}}; # add the children to the deletions todo list
            delete $children->{$type};
        }

        delete $bindings->{$type}; # delete the specified type
    }

    unless (%$children) {
        delete $bindings->{_children}; # harmless if it doesn't exist
    }

    if (%$bindings) {
        _install($bindings);
    } else { # remove all traces of autobox from the current scope
        $^H &= ~0x120000; # unset HINT_LOCALIZE_HH + the additional bit
        delete $^H{autobox};
        delete $^H{autobox_scope};
        delete $^H{autobox_leavescope}; # triggers the leavescope handler
    }
}

1;
