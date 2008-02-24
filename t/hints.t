#!/usr/bin/env perl

use strict;
use warnings;

use Test::More tests => 5;

BEGIN { is($^H & 0x100000, 0x000000) }

no autobox;

BEGIN { is($^H & 0x100000, 0x000000) }

{
    use autobox;
    BEGIN { is($^H & 0x120000, 0x120000) }
    no autobox;
    BEGIN { is($^H & 0x100000, 0x000000) }
    use autobox;
}

BEGIN { is($^H & 0x100000, 0x000000) }
