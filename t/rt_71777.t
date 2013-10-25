# runner for the test case provided by Tomas Doran (t0m)
# https://rt.cpan.org/Ticket/Display.html?id=71777

use strict;
use warnings;

use Test::More tests => 1;

SKIP: {
    skip "perl ($^X) is not executable", 1 unless (-x $^X);
    my $rt71777 = __FILE__;
    $rt71777 =~ s{\.t$}{.pl};
    is system($^X, $rt71777), 0;
}
