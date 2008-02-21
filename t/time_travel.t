#!/usr/bin/env perl

use strict;
use warnings;

use Test::More tests => 7;

use vars qw($string $string_error);

BEGIN {
    $string_error = qr{Can't locate object method "test" via package "Hello, World!"};
    $string = 'Hello, World!';

    no strict 'refs';

    for my $name (qw(Scalar1 Scalar2)) {
	*{"$name\::test"} = sub { __PACKAGE__ };
    }
}

{
    no autobox;

    BEGIN {
	eval { $string->test() };
	ok ($@ && ($@ =~ /^$string_error/));
    }

    use autobox SCALAR => 'Scalar1';

    BEGIN {
	is($string->test(), __PACKAGE__);
    }

    is($string->test(), __PACKAGE__);

    no autobox qw(SCALAR);

    BEGIN {
	eval { $string->test() };
	ok ($@ && ($@ =~ /^$string_error/));
    }

    {
	use autobox SCALAR => 'Scalar2';

	BEGIN {
	    is($string->test(), __PACKAGE__);
	}

	is($string->test(), __PACKAGE__);
    }

    BEGIN {
	eval { $string->test() };
	ok ($@ && ($@ =~ /^$string_error/));
    }
}
