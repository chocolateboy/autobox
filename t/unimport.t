#!/usr/bin/env perl

use strict;
use warnings;

use Test::More tests => 11;

use vars qw($string $string_error $unblessed_error);

BEGIN {
    $string_error = qr{Can't locate object method "test" via package "Hello, World!"};
    $string = 'Hello, World!';

    no strict 'refs';

    for my $name (qw(MyScalar2 MyScalar3 MyScalar5 SCALAR)) {
	*{"$name\::test"} = sub { __PACKAGE__ };
    }
}

{
    no autobox;

    BEGIN {
	eval { $string->test() };
	ok ($@ && ($@ =~ /^$string_error/));
    }

    use autobox;

    BEGIN {
	is($string->test(), __PACKAGE__);
    }

    {
	use autobox SCALAR => 'MyScalar2';
	BEGIN {
	    is($string->test(), __PACKAGE__);
	}
    }

    {
	no autobox;

	BEGIN {
	    eval { $string->test() };
	    ok ($@ && ($@ =~ /^$string_error/));
	}

	use autobox SCALAR => 'MyScalar2';

	BEGIN {
	    is($string->test(), __PACKAGE__);
	}

	use autobox SCALAR => 'MyScalar3';

	BEGIN {
	    is($string->test(), __PACKAGE__);
	}

	is($string->test(), __PACKAGE__);

	no autobox;

	BEGIN {
	    eval { $string->test() };
	    ok ($@ && ($@ =~ /^$string_error/));
	}

	eval { $string->test() };
	ok ($@ && ($@ =~ /^$string_error/));
    }

    {
	no autobox qw(ARRAY);
	use autobox SCALAR => 'MyScalar4';
    }

    no autobox qw(HASH);
    use autobox SCALAR => 'MyScalar5';

    BEGIN {
	is($string->test(), __PACKAGE__);
    }

    is($string->test(), __PACKAGE__);

    no autobox qw(SCALAR);
    use autobox SCALAR => 'MyScalar6';
}
