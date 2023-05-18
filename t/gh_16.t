#!/usr/bin/env perl

use strict;
use warnings;

use Test::More;

BEGIN {
    eval 'use Parallel::ForkManager 2.02';
    plan skip_all => 'Parallel::ForkManager >= 2.02 required for this test' if ($@);
}

use autobox;

sub SCALAR::greet {
    return "Hello, $_[0]!";
}

plan tests => 2;

my @results;
my $pm = Parallel::ForkManager->new(3);

$pm->run_on_finish(
    sub {
        my ($pid, $exit_code, $ident, $exit_signal, $core_dump, $returned) = @_;
        diag "child #$returned->{id} finished";
        push @results, $returned->{id};
    }
);

LOOP:
for my $id (0 .. 9) {
    my $pid = $pm->start and next LOOP;
    diag "child: $id";
    my $return_data = { id => $id };
    $pm->finish(0, $return_data);
}

$pm->wait_all_children;

is('world'->greet, 'Hello, world!', 'autobox');
is_deeply([ sort @results ], [ 0..9 ], 'Parallel::ForkManager');
