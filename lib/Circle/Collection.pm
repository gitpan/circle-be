#  You may distribute under the terms of the GNU General Public License
#
#  (C) Paul Evans, 2008-2010 -- leonerd@leonerd.org.uk

package Circle::Collection;

use strict;

use Carp;
require attributes;

# A template role to merge
sub import
{
   my $pkg = shift;
   my %args = @_;

   my $caller = caller;

   my $name = $args{name} or croak "Need a collection name";

   my $attrs = $args{attrs} or croak "Need attrs";
   ref $attrs eq "ARRAY" or croak "Expected 'attrs' to be an ARRAY";

   my $desc2 = $args{desc_plural} || $name;
   my $desc1 = $args{desc_single} || do { $_ = $name; s/s$//; $_ };

   my $storage = $args{storage} or croak "Need a storage type";

   # Now parse it down to several fields
   my @attr_names;
   my %attrs;

   for( my $i = 0; $i < @$attrs; $i += 2 ) {
      my $name = $attrs->[$i];
      my $a = $attrs->[$i+1];

      push @attr_names, $name;
      $attrs{$name} = $a;
   }

   my $keyattr = $attr_names[0];

   my %commands;
   %commands = %{ $args{commands} } if $args{commands};

   # Data access code

   my ( $method_list, $method_get, $method_add, $method_del );

   if( ref $storage eq "HASH" ) {
      $method_list = $storage->{list};
      $method_get  = $storage->{get};
      $method_add  = $storage->{add};
      $method_del  = $storage->{del};
   }
   elsif( $storage eq "array" ) {
      $method_list = _mksub( $caller,
         sub { 
            my $self = shift;
            return @{ $self->{$name} }
         }
      );

      $method_get = _mksub( $caller,
         sub {
            my $self = shift;
            my ( $key ) = @_;
            return ( grep { $_->{$keyattr} eq $key } @{ $self->{$name} } )[0];
         }
      );

      $method_add = _mksub( $caller,
         sub {
            my $self = shift;
            my ( $key, $item ) = @_;
            # TODO: something with key
            push @{ $self->{$name} }, $item;
         }
      );

      $method_del = _mksub( $caller,
         sub {
            my $self = shift;
            my ( $key, $item ) = @_;

            my $items = $self->{$name};
            my ( $idx ) = grep { $items->[$_] == $item } 0 .. $#$items;

            return 0 unless defined $idx;

            splice @$items, $idx, 1, ();
            return 1;
         }
      );
   }
   else {
      croak "Unrecognised storage type $storage";
   }

   # Manipulation commands

   $commands{list} = _mksub( $caller,
      Command_description => qq("List the $desc2"),
      Command_subof       => qq('$name'),
      Command_default     => qq(),
      sub {
         my $self = shift;
         my ( $cinv ) = @_;

         my @items = $self->$method_list;

         unless( @items ) {
            $cinv->respond( "No $desc2" );
            return;
         }

         my @table;

         foreach my $item ( @items ) {
            my @shown_item;
            foreach my $attr ( @attr_names ) {
               my $value = $item->{$attr};
               push @shown_item, exists $attrs{$attr}{show} ? $attrs{$attr}{show}->( local $_ = $value ) : $value;
            }
            push @table, \@shown_item;
         }

         $cinv->respond_table( \@table, headings => \@attr_names );
         return;
      }
   ) unless exists $commands{list};

   my @opts_add;
   my @opts_mod;

   foreach ( @attr_names ) {
      next if $_ eq $keyattr;

      my $desc = $attrs{$_}{desc} || $_;

      $desc .= qq[ (default \\"$attrs{$_}{default}\\")] if exists $attrs{$_}{default};

      push @opts_add, qq('$_=\$', desc => "$desc");

      push @opts_mod, qq('$_=\$',   desc => "$desc"),
                      qq('no-$_=+', desc => "remove $_") unless $attrs{$_}{nomod};
   }

   $commands{add} = _mksub( $caller,
      Command_description => qq("Add a $desc1"),
      Command_subof       => qq('$name'),
      Command_arg         => qq('$keyattr'),
      Command_opt         => \@opts_add,
      sub {
         my $self = shift;
         my ( $key, $opts, $cinv ) = @_;

         if( $self->$method_get( $key ) ) {
            $cinv->responderr( "Already have a $desc1 '$key'" );
            return;
         }

         my $item = { $keyattr => $key };
         exists $attrs{$_}{default} and $item->{$_} = $attrs{$_}{default} for @attr_names;

         defined $opts->{$_} and $item->{$_} = $opts->{$_} for @attr_names;

         unless( eval { $self->$method_add( $key, $item ); 1 } ) {
            my $err = "$@"; chomp $err;
            $cinv->responderr( "Cannot add $desc1 '$key' - $err" );
            return;
         }

         $cinv->respond( "Added $desc1 '$key'" );
         return;
      }
   ) unless exists $commands{add};

   $commands{mod} = _mksub( $caller,
      Command_description => qq("Modify an existing $desc1"),
      Command_subof       => qq('$name'),
      Command_arg         => qq('$keyattr'),
      Command_opt         => \@opts_mod,
      sub {
         my $self = shift;
         my ( $key, $opts, $cinv ) = @_;

         my $item = $self->$method_get( $key );

         unless( $item ) {
            $cinv->responderr( "No such $desc1 '$key'" );
            return;
         }

         exists $opts->{$_} and $item->{$_} = $opts->{$_} for @attr_names;
         exists $opts->{"no-$_"} and $item->{$_} = $attrs{$_}{default} for @attr_names;

         $cinv->respond( "Modified $desc1 '$key'" );
         return;
      }
   ) unless exists $commands{mod};

   $commands{del} = _mksub( $caller,
      Command_description => qq("Delete a $desc1"),
      Command_subof       => qq('$name'),
      Command_arg         => qq('$keyattr'),
      sub {
         my $self = shift;
         my ( $key, $cinv ) = @_;

         my $item = $self->$method_get( $key );

         unless( $item ) {
            $cinv->responderr( "No such $desc1 '$key'" );
            return;
         }

         unless( eval { $self->$method_del( $key, $item ); 1 } ) {
            my $err = "$@"; chomp $err;
            $cinv->responderr( "Cannot delete $desc1 '$key' - $err" );
            return;
         }

         $cinv->respond( "Removed $desc1 '$key'" );
         return;
      }
   ) unless exists $commands{del};

   # Now delete present-but-undef ones; these are where the caller vetoed the 
   # above autogeneration
   defined $commands{$_} or delete $commands{$_} for keys %commands;

   my %subs;
   $subs{"command_${name}_$_"} = $commands{$_} for keys %commands;

   $subs{"command_${name}"} = _mksub( $caller,
      Command_description => qq("Display or manipulate $desc2"),
      # body matters not but it needs to be a cloned closure
      do { my $dummy; sub { undef $dummy } }
   );

   # Configuration load/store

   $subs{"load_${name}_configuration"} = _mksub( $caller,
      sub {
         my $self = shift;
         my ( $ynode ) = @_;

         foreach my $n ( @{ $ynode->{$name} } ) {
            my $item = {};
            $item->{$_} = $n->{$_} for @attr_names;

            $self->$method_add( $item->{$keyattr}, $item );
         }
      }
   );

   $subs{"store_${name}_configuration"} = _mksub( $caller,
      sub {
         my $self = shift;
         my ( $ynode ) = @_;

         $ynode->{$name} = \my @itemconfs;

         foreach my $item ( $self->$method_list ) {
            push @itemconfs, my $n = YAML::Node->new({});
            defined $item->{$_} and $n->{$_} = $item->{$_} for @attr_names;
         }
      }
   );

   {
      no strict 'refs';
      *{"${caller}::$_"} = $subs{$_} for keys %subs;
   }
}

sub _mksub
{
   my $caller = shift;
   my $code = pop;
   my %attrs = @_;

   foreach my $attr ( keys %attrs ) {
      my $value = $attrs{$attr};
      attributes->import( $caller, $code, "$attr($_)" ) for ref $value ? @$value : ( $value );
   }

   return $code;
}

1;
