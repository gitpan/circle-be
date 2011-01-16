use strict;
use warnings;

use Module::Build;

my $build = Module::Build->new(
   module_name => 'Circle',
   dist_name   => 'circle-be',
   requires => {
      'Attribute::Storage' => '0.05',
      'Data::Dump' => 0,
      'IO::Async::Loop' => '0.16',
      'Net::Async::IRC' => 0,
      'Net::Async::Tangence::Server' => 0,
      'String::Tagged' => 0,
      'Tangence::Object' => '0.03',
      'YAML' => 0,
   },
   license => 'gpl',
   create_makefile_pl => 'traditional',
   create_license => 1,
   create_readme  => 1,
);

$build->create_build_script;
