#  You may distribute under the terms of the GNU General Public License
#
#  (C) Paul Evans, 2008-2010 -- leonerd@leonerd.org.uk

package Circle::Configurable;

use strict;

use base qw( Circle::Commandable );

use Carp;

use Attribute::Storage qw( get_subattr get_subattrs );

#############################################
### Attribute handlers for setting_* subs ###
#############################################

my %setting_types = (
   str => {},

   int => {
      check => sub { m/^\d+$/ },
   },

   bool => {
      parse => sub {
         return 1 if lc $_ eq "true"  or lc $_ eq "on"  or $_ eq "1";
         return 0 if lc $_ eq "false" or lc $_ eq "off" or $_ eq "0";
         die;
      },
      print => sub { $_ ? "true" : "false" },
   },
);

sub Setting_description :ATTR(CODE)
{
   my $class = shift;
   my ( $text ) = @_;

   return $text;
}

sub Setting_type :ATTR(CODE)
{
   my $class = shift;
   my ( $typename ) = @_;

   exists $setting_types{$typename} or croak "Not a recognised type name '$typename'";

   return $setting_types{$typename};
}

sub _get_settings
{
   my $self = shift;

   my $class = ref $self || $self;

   my %settings;

   no strict 'refs';
   foreach my $name ( keys %{$class."::"} ) {
      ( my $settingname = $name ) =~ s/^setting_// or next;

      my $cv = $class->can( $name ) or next;
      $settings{$settingname} = get_subattrs( $cv );
   }

   return \%settings;
}

sub command_set
   : Command_description("Display or manipulate configuration settings")
   : Command_arg('setting?')
   : Command_arg('value?')
   : Command_opt('help=+',   desc => "Display help on setting(s)")
   : Command_opt('values=+', desc => "Display value of each setting")
{
   my $self = shift;
   my ( $setting, $newvalue, $opts, $cinv ) = @_;

   my $opt_help   = $opts->{help};
   my $opt_values = $opts->{values};

   if( !defined $setting ) {
      my $settings = $self->_get_settings;

      keys %$settings or $cinv->respond( "No settings exist" ), return;

      if( $opt_values ) {
         my @table;
         foreach my $settingname ( sort keys %$settings ) {
            my $curvalue = $self->can( "setting_$settingname" )->( $self );
            if( $setting->{type}->{print} ) {
               $curvalue = $setting->{type}->{print}->( $curvalue );
            }
            push @table, [ $settingname, defined $curvalue ? $curvalue : "" ];
         }

         $self->respond_table( \@table, colsep => ": ", headings => [ "Setting", "Value" ] );
      }
      else {
         my @table;
         foreach my $settingname ( sort keys %$settings ) {
            my $setting = $settings->{$settingname};

            push @table, [ $settingname, ( $setting->{Setting_description} || "[no description]" ) ];
         }

         $cinv->respond_table( \@table, colsep => " - ", headings => [ "Setting", "Description" ] );
      }

      return;
   }

   my $cv = $self->can( "setting_$setting" );
   if( !defined $cv ) {
      $cinv->responderr( "No such setting $setting" );
      return;
   }

   if( $opt_help ) {
      my $description = get_subattr( $cv, 'Setting_description' ) || "[no description]";
      $cinv->respond( "$setting - $description" );
      return;
   }

   my $type = get_subattr( $cv, 'Setting_type' );

   my $curvalue;
   if( defined $newvalue ) {
      if( $type->{check} ) {
         local $_ = $newvalue;
         $type->{check}->( $newvalue ) or
            $cinv->responderr( "'$newvalue' is not a valid value for $setting" ), return;
      }

      if( $type->{parse} ) {
         local $_ = $newvalue;
         eval { $newvalue = $type->{parse}->( $newvalue ); 1 } or
            $cinv->responderr( "'$newvalue' is not a valid value for $setting" ), return;
      }

      $curvalue = $cv->( $self, $newvalue );
   }
   else {
      $curvalue = $cv->( $self );
   }

   if( $type->{print} ) {
      local $_ = $curvalue;
      $curvalue = $type->{print}->( $curvalue );
   }

   if( defined $curvalue ) {
      $cinv->respond( "$setting: $curvalue" );
   }
   else {
      $cinv->respond( "$setting is not set" );
   }

   return;
}

sub get_configuration
{
   my $self = shift;

   my $ynode = YAML::Node->new({});
   $self->store_configuration( $ynode );

   return $ynode;
}

sub load_settings
{
   my $self = shift;
   my ( $ynode, @settings ) = @_;

   foreach my $setting ( @settings ) {
      my $cv = $self->can( "setting_$setting" ) or croak "$self has no setting $setting";
      my $value = $ynode->{$setting};
      $cv->( $self, $value ) if defined $value;
   }
}

sub store_settings
{
   my $self = shift;
   my ( $ynode, @settings ) = @_;

   foreach my $setting ( @settings ) {
      my $cv = $self->can( "setting_$setting" ) or croak "$self has no setting $setting";
      my $value = $cv->( $self );
      $ynode->{$setting} = $value if defined $value;
   }
}

1;
