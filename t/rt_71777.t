# simplified version of test case provided by Tomas Doran (t0m)
# https://rt.cpan.org/Ticket/Display.html?id=71777

use strict;
use warnings;

use Test::More tests => 1;

my $TEST = <<'EOS';
use strict;
use warnings;

{
    package Foo;
    use autobox;
    sub DESTROY { $_[0]->{bar}->bar }
}

{
    package Bar;
    sub bar { }
}

my $foo = bless {}, 'Foo';
my $bar = bless {}, 'Bar';

$foo->{bar} = $bar;
$bar->{foo} = $foo;
EOS

is system($^X, '-e', $TEST), 0;
