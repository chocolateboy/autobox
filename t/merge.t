#!/usr/bin/perl

use strict;
use warnings;
use vars qw($WANT $DESCR);

use Test::More tests => 28;

BEGIN {
    $DESCR = [
        'basic',
        'no dup',
        'horizontal merge',
        'vertical merge',
        'horizontal merge of outer scope in inner scope',
        'dup in inner scope',
        'horizontal merge of inner scope in inner scope',
        'vertical merge in inner scope',
        'vertical merge in outer scope again',
        'merge DEFAULT into inner scope and unmerge ARRAY',
        'merge DEFAULT into top-level scope',
        'dup in sub',
        'horizontal merge in sub',
        'vertical merge in sub',
        'new scope with "no autobox"',
        'dup in new scope with "no autobox"',
        'horizontal merge in new scope with "no autobox"',
        'vertical merge in new scope with "no autobox"',
        'arrayref: two classes',
        'arrayref: one dup class',
        'arrayref: one dup class and one new namespace',
        'arrayref: one dup namespace and one new class',
        'arrayref: one new class',
        'arrayref: one new namespace',
        'arrayref: two default classes',
        'arrayref: one dup default class',
        'arrayref: one dup default class and one new default namespace',
        'arrayref: one new default class'
    ];

    $WANT = [
        # 1 - basic (line 257)
        {
          'SCALAR' => [ qw(MyScalar1) ]
        },

        # 2 - no dup (line 258)
        {
          'SCALAR' => [ qw(MyScalar1) ]
        },

        # 3 - horizontal merge (line 259)
        {
          'SCALAR' => [ qw(MyScalar1 MyString1) ]
        },

        # 4 - vertical merge (line 260)
        {
          'ARRAY' => [ qw(MyArray1) ],
          'SCALAR' => [ qw(MyScalar1 MyString1) ]
        },

        # 5 - horizontal merge of outer scope in inner scope (line 263)
        {
          'ARRAY' => [ qw(MyArray1) ],
          'SCALAR' => [ qw(MyScalar1 MyString1 MyScalar2) ]
        },

        # 6 - dup in inner scope (line 264)
        {
          'ARRAY' => [ qw(MyArray1) ],
          'SCALAR' => [ qw(MyScalar1 MyString1 MyScalar2) ]
        },

        # 7 - horizontal merge of inner scope in inner scope (line 265)
        {
          'ARRAY' => [ qw(MyArray1) ],
          'SCALAR' => [ qw(MyScalar1 MyString1 MyScalar2 MyString2) ]
        },

        # 8 - vertical merge in inner scope (line 266)
        {
          'ARRAY' => [ qw(MyArray1 MyArray2) ],
          'SCALAR' => [ qw(MyScalar1 MyString1 MyScalar2 MyString2) ]
        },

        # 9 - vertical merge in outer scope again (line 269)
        {
          'ARRAY' => [ qw(MyArray1) ],
          'HASH' => [ qw(MyHash3) ],
          'SCALAR' => [ qw(MyScalar1 MyString1) ]
        },

        # 10 - merge DEFAULT into inner scope and unmerge ARRAY (line 273)
        {
          'ARRAY' => [ qw(MyDefault4) ],
          'CODE' => [ qw(MyDefault4) ],
          'HASH' => [ qw(MyHash3 MyDefault4) ],
          'SCALAR' => [ qw(MyScalar1 MyString1 MyDefault4) ]
        },

        # 11 - merge DEFAULT into top-level scope (line 277)
        {
          'ARRAY' => [ qw(MyArray1 MyDefault5) ],
          'CODE' => [ qw(MyDefault5) ],
          'HASH' => [ qw(MyHash3 MyDefault5) ],
          'SCALAR' => [ qw(MyScalar1 MyString1 MyDefault5) ]
        },

        # 12 - dup in sub (line 278)
        {
          'ARRAY' => [ qw(MyArray1 MyDefault5) ],
          'CODE' => [ qw(MyDefault5) ],
          'HASH' => [ qw(MyHash3 MyDefault5) ],
          'SCALAR' => [ qw(MyScalar1 MyString1 MyDefault5) ]
        },

        # 13 - horizontal merge in sub (line 279)
        {
          'ARRAY' => [ qw(MyArray1 MyDefault5) ],
          'CODE' => [ qw(MyDefault5) ],
          'HASH' => [ qw(MyHash3 MyDefault5) ],
          'SCALAR' => [ qw(MyScalar1 MyString1 MyDefault5 MyScalar5) ]
        },

        # 14 - vertical merge in sub (line 280)
        {
          'ARRAY' => [ qw(MyArray1 MyDefault5) ],
          'CODE' => [ qw(MyDefault5) ],
          'HASH' => [ qw(MyHash3 MyDefault5) ],
          'SCALAR' => [ qw(MyScalar1 MyString1 MyDefault5 MyScalar5) ],
          'UNDEF' => [ qw(MyUndef5) ]
        },

        # 15 - new scope with "no autobox" (line 285)
        {
          'SCALAR' => [ qw(MyScalar6) ]
        },

        # 16 - dup in new scope with "no autobox" (line 286)
        {
          'SCALAR' => [ qw(MyScalar6) ]
        },

        # 17 - horizontal merge in new scope with "no autobox" (line 287)
        {
          'SCALAR' => [ qw(MyScalar6 MyString6) ]
        },

        # 18 - vertical merge in new scope with "no autobox" (line 288)
        {
          'ARRAY' => [ qw(MyArray6) ],
          'SCALAR' => [ qw(MyScalar6 MyString6) ]
        },

        # 19 - arrayref: two classes (line 292)
        {
          'ARRAY' => [ qw(MyArray1) ],
          'HASH' => [ qw(MyHash3) ],
          'SCALAR' => [ qw(MyScalar1 MyString1 MyScalar7 MyScalar8) ]
        },

        # 20 - arrayref: one dup class (line 293)
        {
          'ARRAY' => [ qw(MyArray1) ],
          'HASH' => [ qw(MyHash3) ],
          'SCALAR' => [ qw(MyScalar1 MyString1 MyScalar7 MyScalar8) ]
        },

        # 21 - arrayref: one dup class and one new namespace (line 294)
        {
          'ARRAY' => [ qw(MyArray1) ],
          'HASH' => [ qw(MyHash3) ],
          'SCALAR' => [ qw(MyScalar1 MyString1 MyScalar7 MyScalar8 MyScalar10::SCALAR) ]
        },

        # 22 - arrayref: one dup namespace and one new class (line 295)
        {
          'ARRAY' => [ qw(MyArray1) ],
          'HASH' => [ qw(MyHash3) ],
          'SCALAR' => [ qw(MyScalar1 MyString1 MyScalar7 MyScalar8 MyScalar10::SCALAR MyScalar11) ]
        },

        # 23 - arrayref: one new class (line 296)
        {
          'ARRAY' => [ qw(MyArray1 MyArray7) ],
          'HASH' => [ qw(MyHash3) ],
          'SCALAR' => [ qw(MyScalar1 MyString1 MyScalar7 MyScalar8 MyScalar10::SCALAR MyScalar11) ]
        },

        # 24 - arrayref: one new namespace (line 297)
        {
          'ARRAY' => [ qw(MyArray1 MyArray7 MyArray8::ARRAY) ],
          'HASH' => [ qw(MyHash3) ],
          'SCALAR' => [ qw(MyScalar1 MyString1 MyScalar7 MyScalar8 MyScalar10::SCALAR MyScalar11) ]
        },

        # 25 - arrayref: two default classes (line 301)
        {
          'ARRAY' => [ qw(MyArray1 MyDefault6 MyDefault7) ],
          'CODE' => [ qw(MyDefault6 MyDefault7) ],
          'HASH' => [ qw(MyHash3 MyDefault6 MyDefault7) ],
          'SCALAR' => [ qw(MyScalar1 MyString1 MyDefault6 MyDefault7) ]
        },

        # 26 - arrayref: one dup default class (line 302)
        {
          'ARRAY' => [ qw(MyArray1 MyDefault6 MyDefault7) ],
          'CODE' => [ qw(MyDefault6 MyDefault7) ],
          'HASH' => [ qw(MyHash3 MyDefault6 MyDefault7) ],
          'SCALAR' => [ qw(MyScalar1 MyString1 MyDefault6 MyDefault7) ]
        },

        # 27 - arrayref: one dup default class and one new default namespace (line 303)
        {
          'ARRAY' => [ qw(MyArray1 MyDefault6 MyDefault7 MyDefault8::ARRAY) ],
          'CODE' => [ qw(MyDefault6 MyDefault7 MyDefault8::CODE) ],
          'HASH' => [ qw(MyHash3 MyDefault6 MyDefault7 MyDefault8::HASH) ],
          'SCALAR' => [ qw(MyScalar1 MyString1 MyDefault6 MyDefault7 MyDefault8::SCALAR) ]
        },

        # 28 - arrayref: one new default class (line 304)
        {
          'ARRAY' => [ qw(MyArray1 MyDefault6 MyDefault7 MyDefault8::ARRAY MyDefault9) ],
          'CODE' => [ qw(MyDefault6 MyDefault7 MyDefault8::CODE MyDefault9) ],
          'HASH' => [ qw(MyHash3 MyDefault6 MyDefault7 MyDefault8::HASH MyDefault9) ],
          'SCALAR' => [ qw(MyScalar1 MyString1 MyDefault6 MyDefault7 MyDefault8::SCALAR MyDefault9) ]
        },
    ];
}

sub debug {
    my $hash = shift;
    my $descr = sprintf '%s (line %d)', shift(@$DESCR), (caller(2))[2];
    delete @{$hash}{qw(FLOAT INTEGER NUMBER STRING)}; # delete these to confirm that this old test still passes

    # $| = 1;
    # my $counter = 0 if (0);
    # use Data::Dumper; $Data::Dumper::Terse = $Data::Dumper::Indent = $Data::Dumper::Sortkeys = 1;
    # chomp (my $dump = Dumper($hash));
    # printf STDERR "%d - %s\n", ++$counter, $descr;
    # print STDERR "$dump,", $/, $/;

    is_deeply($hash, shift(@$WANT), $descr);
}

no autobox; # make sure a leading "no autobox" doesn't cause any underflow damage

{
    no autobox; # likewise a nested one
}

sub test1 {
    no autobox; # and one in a sub
}

use autobox SCALAR => 'MyScalar1', DEBUG => \&debug;
use autobox SCALAR => 'MyScalar1', DEBUG => \&debug;
use autobox SCALAR => 'MyString1', DEBUG => \&debug;
use autobox ARRAY  => 'MyArray1',  DEBUG => \&debug;

{
    use autobox SCALAR => 'MyScalar2', DEBUG => \&debug;
    use autobox SCALAR => 'MyScalar2', DEBUG => \&debug;
    use autobox SCALAR => 'MyString2', DEBUG => \&debug;
    use autobox ARRAY  => 'MyArray2',  DEBUG => \&debug;
}

use autobox HASH => 'MyHash3', DEBUG => \&debug;

sub sub2 {
    no autobox 'ARRAY';
    use autobox DEFAULT => 'MyDefault4', DEBUG => \&debug;
}

sub sub3 {
    use autobox DEFAULT => 'MyDefault5', DEBUG => \&debug;
    use autobox DEFAULT => 'MyDefault5', DEBUG => \&debug;
    use autobox SCALAR  => 'MyScalar5',  DEBUG => \&debug;
    use autobox UNDEF   => 'MyUndef5',   DEBUG => \&debug;
}

{
    no autobox;
    use autobox SCALAR => 'MyScalar6', DEBUG => \&debug;
    use autobox SCALAR => 'MyScalar6', DEBUG => \&debug;
    use autobox SCALAR => 'MyString6', DEBUG => \&debug;
    use autobox ARRAY  => 'MyArray6',  DEBUG => \&debug;
}

{
    use autobox SCALAR => [ 'MyScalar7', 'MyScalar8' ], DEBUG => \&debug;
    use autobox SCALAR => [ 'MyScalar7' ], DEBUG => \&debug;
    use autobox SCALAR => [ 'MyScalar7',    'MyScalar10::' ], DEBUG => \&debug;
    use autobox SCALAR => [ 'MyScalar10::', 'MyScalar11' ],   DEBUG => \&debug;
    use autobox ARRAY => [ 'MyArray7' ],   DEBUG => \&debug;
    use autobox ARRAY => [ 'MyArray8::' ], DEBUG => \&debug;
}

{
    use autobox DEFAULT => [ 'MyDefault6', 'MyDefault7' ], DEBUG => \&debug;
    use autobox DEFAULT => [ 'MyDefault6' ], DEBUG => \&debug;
    use autobox DEFAULT => [ 'MyDefault6', 'MyDefault8::' ], DEBUG => \&debug;
    use autobox DEFAULT => [ 'MyDefault9' ], DEBUG => \&debug;
}
