#!/usr/bin/env perl

# https://github.com/scrottie/autobox-Core/issues/34

use strict;
use warnings;

use FindBin qw($Bin);
use IPC::System::Simple qw(capturex);
use Test::More tests => 1;

$ENV{PERLDB_OPTS} = 'NonStop=1';

chomp(my $got = capturex($^X, '-d', "$Bin/debugger.pl"));
isnt index($got, 'foo -> bar -> baz -> quux'), -1, 'runs under perl -d';
