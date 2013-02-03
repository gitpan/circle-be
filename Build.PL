use strict;
use warnings;

use Module::Build;

my $build = Module::Build->new(
   module_name => 'Circle',
   dist_name   => 'circle-be',
   requires => {
      'Attribute::Storage' => '0.05',
      'Data::Dump' => 0,
      'File::ShareDir' => 0,
      'IO::Async::Notifier' => '0.43',
      'IO::Async::Loop' => '0.37',
      'Net::Async::IRC' => '0.04',
      'Net::Async::Tangence::Server' => 0,
      'String::Tagged' => 0,
      'Tangence::Message' => '0.11', # for bugfix to objset serialisation
      'Tangence::Object' => '0.06',
      'YAML' => 0,
      'perl' => '5.010',
   },
   build_requires => {
      'Test::Identity' => 0,
      'Test::More' => 0,
   },
   auto_configure_requires => 0, # Don't add M::B to configure_requires
   share_dir => {
      module => { "Circle" => "share" },
   },
   license => 'gpl',
   create_makefile_pl => 'traditional',
   create_license => 1,
   create_readme  => 1,
);

$build->create_build_script;