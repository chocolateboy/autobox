use 5.008;
use ExtUtils::MakeMaker;

# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.

my $optimize = ($^O eq 'MSWin32') ? '-O2 -W4' : '-O3 -Wall';

WriteMakefile(
    NAME            => 'autobox',
    VERSION_FROM    => 'autobox.pm', # finds $VERSION
    INSTALLDIRS     => 'perl',
    PREREQ_PM       => {
        'XSLoader'       => 0,
        'Test::More'     => 0,
        'Scope::Guard'   => '0.03',
        'Scalar::Util'   => '1.19',
    }, # e.g., Module::Name => 1.1
    ABSTRACT_FROM        => 'autobox.pod', # retrieve abstract from module
    AUTHOR               => 'chocolateboy <chocolate.boy@email.com>',
    LIBS                 => [''], # e.g., '-lm'
    DEFINE               => '', # e.g., '-DHAVE_SOMETHING'
    INC                  => '-I.', # e.g., '-I. -I/usr/include/other'
    OPTIMIZE             => $optimize,
    # OPTIMIZE           => '-E',
    # Un-comment this if you add C files to link with later:
    # OBJECT             => '$(O_FILES)', # link all the C files too
);
