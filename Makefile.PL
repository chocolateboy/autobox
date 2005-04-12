use 5.006001;
use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    NAME              => 'autobox',
    VERSION_FROM      => 'autobox.pm', # finds $VERSION
    INSTALLDIRS		  => 'perl',
    PREREQ_PM         => {
		'XSLoader'			=> 0,
		'Test::More'		=> 0,
		'Scope::Guard'		=> 0,
	}, # e.g., Module::Name => 1.1
    ($] >= 5.005 ?     ## Add these new keywords supported since 5.005
      (ABSTRACT_FROM  => 'autobox.pm', # retrieve abstract from module
       AUTHOR         => 'chocolateboy <chocolate.boy@email.com>') : ()),
    LIBS              => [''], # e.g., '-lm'
    DEFINE            => '', # e.g., '-DHAVE_SOMETHING'
    INC               => '-I.', # e.g., '-I. -I/usr/include/other'
    OPTIMIZE		  => '-O3 -Wall',
	# Un-comment this if you add C files to link with later:
    # OBJECT            => '$(O_FILES)', # link all the C files too
);
