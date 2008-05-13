use 5.008;
use ExtUtils::MakeMaker;

my $optimize = ($^O eq 'MSWin32') ? '-O2 -W4' : '-O3 -Wall';

WriteMakefile(
    NAME            => 'autobox',
    VERSION_FROM    => 'autobox.pm',
    INSTALLDIRS     => 'perl',
    PREREQ_PM       => {
        'Scope::Guard'   => '0.03',
    },
    ABSTRACT_FROM        => 'autobox.pod',
    AUTHOR               => 'chocolateboy <chocolate.boy@email.com>',
    INC                  => '-I.',
    OPTIMIZE             => $optimize,
    ($ExtUtils::MakeMaker::VERSION >= 6.31 ? (LICENSE => 'perl') : ()),
);
