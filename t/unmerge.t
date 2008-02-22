#!/usr/bin/env perl

use strict;
use warnings;

use Test::More tests => 40;

use vars qw($string $string_error $unblessed_error);

BEGIN {
    $string = 'Hello, world!';
    $string_error = qr{Can't locate object method "test" via package "$string"};
    $unblessed_error = qr{Can't call method "test" on unblessed reference\b};

    no strict 'refs';

    for my $name (qw(SCALAR ARRAY HASH CODE Scalar1 Scalar2)) {
        *{"$name\::test"} = sub { $name };
    }
}

{
    no autobox;

    BEGIN {
        eval { $string->test() };
        ok ($@ && ($@ =~ /^$string_error/));
    }

    eval { $string->test() };
    ok ($@ && ($@ =~ /^$string_error/));

    use autobox SCALAR => 'Scalar1';

    BEGIN {
        is($string->test(), 'Scalar1');
    }

    is($string->test(), 'Scalar1');

    no autobox qw(SCALAR);

    BEGIN {
        eval { $string->test() };
        ok ($@ && ($@ =~ /^$string_error/));
    }

    eval { $string->test() };
    ok ($@ && ($@ =~ /^$string_error/));

    {
        use autobox SCALAR => 'Scalar2';

        BEGIN {
            is($string->test(), 'Scalar2');
        }

        is($string->test(), 'Scalar2');

        no autobox;
    }

    use autobox;

    BEGIN {
        is(''->test(), 'SCALAR');
        is([]->test(), 'ARRAY');
        is({}->test(), 'HASH');
        is(sub {}->test(), 'CODE');
    }

    is(''->test(), 'SCALAR');
    is([]->test(), 'ARRAY');
    is({}->test(), 'HASH');
    is(sub {}->test(), 'CODE');

    no autobox qw(SCALAR);

    BEGIN {
        eval { $string->test() };
        ok ($@ && ($@ =~ /^$string_error/));
    }

    eval { $string->test() };
    ok ($@ && ($@ =~ /^$string_error/));

    BEGIN {
        is([]->test(), 'ARRAY');
        is({}->test(), 'HASH');
        is(sub {}->test(), 'CODE');
    }

    is([]->test(), 'ARRAY');
    is({}->test(), 'HASH');
    is(sub {}->test(), 'CODE');

    no autobox qw(ARRAY HASH);

    BEGIN {
        eval { $string->test() };
        ok ($@ && ($@ =~ /^$string_error/));
    }

    eval { $string->test() };
    ok ($@ && ($@ =~ /^$string_error/));

    BEGIN {
        eval { []->test() };
        ok ($@ && ($@ =~ /^$unblessed_error/));
        eval { {}->test() };
        ok ($@ && ($@ =~ /^$unblessed_error/));
    }

    eval { []->test() };
    ok ($@ && ($@ =~ /^$unblessed_error/));
    eval { {}->test() };
    ok ($@ && ($@ =~ /^$unblessed_error/));

    BEGIN {
        is(sub {}->test(), 'CODE');
    }

    is(sub {}->test(), 'CODE');

    no autobox;

    BEGIN {
        eval { $string->test() };
        ok ($@ && ($@ =~ /^$string_error/));
        eval { []->test() };
        ok ($@ && ($@ =~ /^$unblessed_error/));
        eval { {}->test() };
        ok ($@ && ($@ =~ /^$unblessed_error/));
        eval { sub {}->test() };
        ok ($@ && ($@ =~ /^$unblessed_error/));
    }

    eval { $string->test() };
    ok ($@ && ($@ =~ /^$string_error/));
    eval { []->test() };
    ok ($@ && ($@ =~ /^$unblessed_error/));
    eval { {}->test() };
    ok ($@ && ($@ =~ /^$unblessed_error/));
    eval { sub {}->test() };
    ok ($@ && ($@ =~ /^$unblessed_error/));
}
