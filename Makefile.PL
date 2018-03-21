use inc::Module::Install;

RTx 'RT-Extension-GSuite';
abstract_from 'lib/RT/Extension/GSuite.pm';
license 'perl';
author_from 'lib/RT/Extension/GSuite.pm';
version_from 'lib/RT/Extension/GSuite.pm';

requires_rt('4.0.0');
requires 'Furl' => '3.07';
requires 'Data::Validator' => '1.07';
requires 'Mojo::Collection' => 0;
requires 'Mojo::JWT::Google' => 0;
requires 'JSON' => '2.90';
requires 'Sub::Retry' => '0.06';
requires 'Mouse' => 0;
requires 'URI::Escape' => 0;
test_requires 'Test::MockObject';
# test_requires 'Test::Routine';
auto_install();

my ($lp) = ($INC{'RT.pm'} =~ /^(.*)[\\\/]/);
my $lib_path = join( ' ', "$RT::LocalPath/lib", $lp );
my $sbin_path = $RT::SbinPath || "$RT::BasePath/sbin" || "/opt/rt4/sbin";
my $bin_path = $RT::BinPath || "$RT::BasePath/bin" || "/opt/rt4/bin";

substitute(
    {
        RT_LIB_PATH  => $lib_path,
        RT_BIN_PATH  => $bin_path,
        RT_SBIN_PATH => $sbin_path,
    },
    {
        sufix => '.in',
    },
    qw(
        lib/RT/Extension/GSuite/Test.pm
    ),
);
tests 'xt/*.t xt/*/*.t';

sign;
&WriteAll;
