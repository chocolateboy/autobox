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

        # 1 - basic
	{
	  'SCALAR' => 'autobox::scalar::<1> (MyScalar1)'
	},

        # 2 - no dup
	{
	  'SCALAR' => 'autobox::scalar::<1> (MyScalar1)'
	},

        # 3 - horizontal merge
	{
	  'SCALAR' => 'autobox::scalar::<1> (MyScalar1, MyString1)'
	},

        # 4 - vertical merge
	{
	  'ARRAY' => 'autobox::array::<2> (MyArray1)',
	  'SCALAR' => 'autobox::scalar::<1> (MyScalar1, MyString1)'
	},

        # 5 - horizontal merge of outer scope in inner scope
	{
	  'ARRAY' => 'autobox::array::<2> (MyArray1)',
	  'SCALAR' => 'autobox::scalar::<3> (MyScalar1, MyString1, MyScalar2)'
	},

        # 6 - dup in inner scope
	{
	  'ARRAY' => 'autobox::array::<2> (MyArray1)',
	  'SCALAR' => 'autobox::scalar::<3> (MyScalar1, MyString1, MyScalar2)'
	},

        # 7 - horizontal merge of inner scope in inner scope
	{
	  'ARRAY' => 'autobox::array::<2> (MyArray1)',
	  'SCALAR' => 'autobox::scalar::<3> (MyScalar1, MyString1, MyScalar2, MyString2)'
	},

        # 8 - vertical merge in inner scope
	{
	  'ARRAY' => 'autobox::array::<2> (MyArray1, MyArray2)',
	  'SCALAR' => 'autobox::scalar::<3> (MyScalar1, MyString1, MyScalar2, MyString2)'
	},

        # 9 - vertical merge in outer scope again
	{
	  'ARRAY' => 'autobox::array::<2> (MyArray1, MyArray2)',
	  'HASH' => 'autobox::hash::<4> (MyHash3)',
	  'SCALAR' => 'autobox::scalar::<1> (MyScalar1, MyString1)'
	},

        # 10 - merge DEFAULT into inner scope and unmerge ARRAY
	{
	  'CODE' => 'autobox::code::<5> (MyDefault4)',
	  'HASH' => 'autobox::hash::<7> (MyHash3, MyDefault4)',
	  'ARRAY' => 'autobox::array::<6> (MyDefault4)',
	  'SCALAR' => 'autobox::scalar::<8> (MyScalar1, MyString1, MyDefault4)'
	},

        # 11 - merge DEFAULT into top-level scope
	{
	  'CODE' => 'autobox::code::<9> (MyDefault5)',
	  'HASH' => 'autobox::hash::<11> (MyHash3, MyDefault5)',
	  'ARRAY' => 'autobox::array::<10> (MyDefault5)',
	  'SCALAR' => 'autobox::scalar::<12> (MyScalar1, MyString1, MyDefault5)'
	},

        # 12 - dup in sub
	{
	  'CODE' => 'autobox::code::<9> (MyDefault5)',
	  'HASH' => 'autobox::hash::<11> (MyHash3, MyDefault5)',
	  'ARRAY' => 'autobox::array::<10> (MyDefault5)',
	  'SCALAR' => 'autobox::scalar::<12> (MyScalar1, MyString1, MyDefault5)'
	},

        # 13 - horizontal merge in sub
	{
	  'CODE' => 'autobox::code::<9> (MyDefault5)',
	  'HASH' => 'autobox::hash::<11> (MyHash3, MyDefault5)',
	  'ARRAY' => 'autobox::array::<10> (MyDefault5)',
	  'SCALAR' => 'autobox::scalar::<12> (MyScalar1, MyString1, MyDefault5, MyScalar5)'
	},

        # 14 - vertical merge in sub
	{
	  'CODE' => 'autobox::code::<9> (MyDefault5)',
	  'UNDEF' => 'autobox::undef::<13> (MyUndef5)',
	  'HASH' => 'autobox::hash::<11> (MyHash3, MyDefault5)',
	  'ARRAY' => 'autobox::array::<10> (MyDefault5)',
	  'SCALAR' => 'autobox::scalar::<12> (MyScalar1, MyString1, MyDefault5, MyScalar5)'
	},

        # 15 - new scope with "no autobox"
	{
	  'SCALAR' => 'autobox::scalar::<14> (MyScalar6)'
	},

        # 16 - dup in new scope with "no autobox"
	{
	  'SCALAR' => 'autobox::scalar::<14> (MyScalar6)'
	},

        # 17 - horizontal merge in new scope with "no autobox"
	{
	  'SCALAR' => 'autobox::scalar::<14> (MyScalar6, MyString6)'
	},

        # 18 - vertical merge in new scope with "no autobox"
	{
	  'ARRAY' => 'autobox::array::<15> (MyArray6)',
	  'SCALAR' => 'autobox::scalar::<14> (MyScalar6, MyString6)'
	},

        # 19 - arrayref: two classes
	{
	  'SCALAR' => 'autobox::scalar::<16> (MyScalar7, MyScalar8)'
	},

        # 20 - arrayref: one dup class
	{
	  'SCALAR' => 'autobox::scalar::<16> (MyScalar7, MyScalar8)'
	},

        # 21 - arrayref: one dup class and one new namespace
	{
	  'SCALAR' => 'autobox::scalar::<16> (MyScalar7, MyScalar8, MyScalar10::SCALAR)'
	},

        # 22 - arrayref: one dup namespace and one new class
	{
	  'SCALAR' => 'autobox::scalar::<16> (MyScalar7, MyScalar8, MyScalar10::SCALAR, MyScalar11)'
	},

        # 23 - arrayref: one new class
	{
	  'ARRAY' => 'autobox::array::<17> (MyArray7)',
	  'SCALAR' => 'autobox::scalar::<16> (MyScalar7, MyScalar8, MyScalar10::SCALAR, MyScalar11)'
	},

        # 24 - arrayref: one new namespace
	{
	  'ARRAY' => 'autobox::array::<17> (MyArray7, MyArray8::ARRAY)',
	  'SCALAR' => 'autobox::scalar::<16> (MyScalar7, MyScalar8, MyScalar10::SCALAR, MyScalar11)'
	},

	# 25 - arrayref: two default classes
	{
	  'CODE' => 'autobox::code::<18> (MyDefault6, MyDefault7)',
	  'ARRAY' => 'autobox::array::<19> (MyDefault6, MyDefault7)',
	  'HASH' => 'autobox::hash::<20> (MyDefault6, MyDefault7)',
	  'SCALAR' => 'autobox::scalar::<21> (MyDefault6, MyDefault7)'
	},

	# 26 - arrayref: one dup default class
	{
	  'CODE' => 'autobox::code::<18> (MyDefault6, MyDefault7)',
	  'ARRAY' => 'autobox::array::<19> (MyDefault6, MyDefault7)',
	  'HASH' => 'autobox::hash::<20> (MyDefault6, MyDefault7)',
	  'SCALAR' => 'autobox::scalar::<21> (MyDefault6, MyDefault7)'
	},

	# 27 - arrayref: one dup default class and one new default namespace
	{
	  'CODE' => 'autobox::code::<18> (MyDefault6, MyDefault7, MyDefault8::CODE)',
	  'ARRAY' => 'autobox::array::<19> (MyDefault6, MyDefault7, MyDefault8::CODE)',
	  'HASH' => 'autobox::hash::<20> (MyDefault6, MyDefault7, MyDefault8::CODE)',
	  'SCALAR' => 'autobox::scalar::<21> (MyDefault6, MyDefault7, MyDefault8::CODE)'
	},

	# 28 - arrayref: one new default class
	{
	  'CODE' => 'autobox::code::<18> (MyDefault6, MyDefault7, MyDefault8::CODE, MyDefault9)',
	  'ARRAY' => 'autobox::array::<19> (MyDefault6, MyDefault7, MyDefault8::CODE, MyDefault9)',
	  'HASH' => 'autobox::hash::<20> (MyDefault6, MyDefault7, MyDefault8::CODE, MyDefault9)',
	  'SCALAR' => 'autobox::scalar::<21> (MyDefault6, MyDefault7, MyDefault8::CODE, MyDefault9)'
	},

    ];
}

sub debug {
    my $hash  = autobox::annotate(shift);
    my $descr = shift @$DESCR;

    # $| = 1;
    # use Data::Dumper; $Data::Dumper::Terse = $Data::Dumper::Indent = 1;
    # print STDERR Dumper($hash), $/;

    is_deeply(shift(@$WANT), $hash, $descr);
}

no autobox; # make sure a leading"no autobox" doesn't cause any underflow damage

{
    no autobox; # likewise a nested one
}

sub test1 {
    no autobox; # and one in a sub
}

use autobox SCALAR => 'MyScalar1',DEBUG => \&debug;
use autobox SCALAR => 'MyScalar1',DEBUG => \&debug;
use autobox SCALAR => 'MyString1',DEBUG => \&debug;
use autobox ARRAY  => 'MyArray1', DEBUG => \&debug;

{
    use autobox SCALAR => 'MyScalar2',DEBUG => \&debug;
    use autobox SCALAR => 'MyScalar2',DEBUG => \&debug;
    use autobox SCALAR => 'MyString2',DEBUG => \&debug;
    use autobox ARRAY  => 'MyArray2', DEBUG => \&debug;
}

use autobox HASH => 'MyHash3', DEBUG => \&debug;

sub sub2 {
    no autobox 'ARRAY';
    use autobox DEFAULT => 'MyDefault4', DEBUG => \&debug;
}

sub sub3 {
    use autobox DEFAULT => 'MyDefault5',   DEBUG => \&debug;
    use autobox DEFAULT => 'MyDefault5',   DEBUG => \&debug;
    use autobox SCALAR  => 'MyScalar5', DEBUG => \&debug;
    use autobox UNDEF   => 'MyUndef5',  DEBUG => \&debug;
}

{
    no autobox;
    use autobox SCALAR => 'MyScalar6',DEBUG => \&debug;
    use autobox SCALAR => 'MyScalar6',DEBUG => \&debug;
    use autobox SCALAR => 'MyString6',DEBUG => \&debug;
    use autobox ARRAY  => 'MyArray6', DEBUG => \&debug;
}

{
    use autobox SCALAR => [ 'MyScalar7', 'MyScalar8' ], DEBUG => \&debug;
    use autobox SCALAR => [ 'MyScalar7' ], DEBUG => \&debug;
    use autobox SCALAR => [ 'MyScalar7', 'MyScalar10::' ], DEBUG => \&debug;
    use autobox SCALAR => [ 'MyScalar10::', 'MyScalar11' ], DEBUG => \&debug;
    use autobox ARRAY  => [ 'MyArray7' ], DEBUG => \&debug;
    use autobox ARRAY  => [ 'MyArray8::' ], DEBUG => \&debug;
}

{
    use autobox DEFAULT  => [ 'MyDefault6', 'MyDefault7' ], DEBUG => \&debug;
    use autobox DEFAULT  => [ 'MyDefault6' ], DEBUG => \&debug;
    use autobox DEFAULT  => [ 'MyDefault6', 'MyDefault8::' ], DEBUG => \&debug;
    use autobox DEFAULT  => [ 'MyDefault9' ], DEBUG => \&debug;
}
