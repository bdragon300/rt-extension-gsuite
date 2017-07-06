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
auto_install();

sign;
&WriteAll;