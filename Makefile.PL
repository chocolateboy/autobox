use 5.008;

use strict;
use warnings;

use ExtUtils::MakeMaker;
use Config;

my $OPTIMIZE;

if ($Config{gccversion}) {
    $OPTIMIZE = '-O3 -Wall';
    $OPTIMIZE .= ' -g -Wextra -Wdeclaration-after-statement' if (-d 'dev');
} elsif ($Config{osname} eq 'MSWin32') {
    $OPTIMIZE = '-O2 -W4';
} else {
    $OPTIMIZE = $Config{optimize};
}

WriteMakefile(
    NAME            => 'autobox',
    VERSION_FROM    => 'lib/autobox.pm',
    INSTALLDIRS     => 'perl',
    PREREQ_PM       => {
        'Scope::Guard'   => '0.20',
    },
    ABSTRACT_FROM        => 'lib/autobox.pod',
    AUTHOR               => 'chocolateboy <chocolate@cpan.org>',
    INC                  => '-I.',
    OPTIMIZE             => $OPTIMIZE,
    ($ExtUtils::MakeMaker::VERSION ge 6.31 ? (LICENSE => 'perl') : ()),
    ($ExtUtils::MakeMaker::VERSION ge 6.46 ?
        (META_MERGE => {
            resources => {
                repository => 'http://github.com/chocolateboy/autobox',
            },
        })
        : ()
    ),
);
