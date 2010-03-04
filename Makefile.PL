use inc::Module::Install;

name 'CatalystX-AppBuilder';
all_from 'lib/CatalystX/AppBuilder.pm';

requires 'Catalyst'         => 5.80015; # not sure if it works
requires 'Moose'            => 0;
requires 'namespace::clean' => 0;

test_requires 'Test::More';
auto_set_repository;

WriteAll;