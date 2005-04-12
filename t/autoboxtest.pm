package autoboxtest;

use strict;
use warnings;

our $VERSION = '1.23';
our $value = '';

sub import {
	$VERSION = '3.14';
}

sub unimport {
	$value = 'unimport';
}

sub test {
	return $value;
}

1;
