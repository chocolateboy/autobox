use 5.008;

use ExtUtils::MakeMaker;
use Config;

my $optimize;

if ($Config{gccversion}) {
    $optimize = '-O3 -Wall';
} elsif ($Config{osname} eq 'MSWin32') {
    $optimize = '-O2 -W4';
} else {
    $optimize = $Config{optimize};
}

WriteMakefile(
    NAME            => 'autobox',
    VERSION_FROM    => 'lib/autobox.pm',
    INSTALLDIRS     => 'perl',
    PREREQ_PM       => {
        'Scope::Guard'   => '0.03',
    },
    ABSTRACT_FROM        => 'lib/autobox.pod',
    AUTHOR               => 'chocolateboy <chocolate.boy@email.com>',
    INC                  => '-I.',
    OPTIMIZE             => $optimize,
    ($ExtUtils::MakeMaker::VERSION >= 6.31 ? (LICENSE => 'perl') : ()),
);
