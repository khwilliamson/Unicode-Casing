use ExtUtils::MakeMaker;
use ExtUtils::Depends;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
my $pkg = ExtUtils::Depends->new('Unicode::Casing',
                                 'B::Hooks::OP::Check',
                                 'B::Hooks::OP::PPAddr');
WriteMakefile(
    NAME              => 'Unicode::Casing',
    VERSION_FROM      => 'lib/Unicode/Casing.pm', # finds $VERSION
    PREREQ_PM         => {}, # e.g., Module::Name => 1.1
    ($] >= 5.005 ?     ## Add these new keywords supported since 5.005
      (ABSTRACT_FROM  => 'lib/Unicode/Casing.pm', # retrieve abstract from module
       AUTHOR         => 'Karl Williamson <khw@(none)>') : ()),
    LIBS              => [''], # e.g., '-lm'
    DEFINE            => '', # e.g., '-DHAVE_SOMETHING'
    INC               => '-I.', # e.g., '-I. -I/usr/include/other'
	# Un-comment this if you add C files to link with later:
    # OBJECT            => '$(O_FILES)', # link all the C files too
    $pkg->get_makefile_vars,
);
