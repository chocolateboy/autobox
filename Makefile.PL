require 5.008_001;

use ExtUtils::MakeMaker;

WriteMakefile(
    'NAME'		=> 'autobox',
    'VERSION_FROM'	=> 'lib/autobox.pm',
    'INSTALLDIRS'       => 'perl',
    'PREREQ_PM'		=> { }
);
