#  You may distribute under the terms of the GNU General Public License
#
#  (C) Paul Evans, 2008-2011 -- leonerd@leonerd.org.uk

package Circle::Net::Raw;

use strict;
use warnings;

use base qw( Tangence::Object Circle::WindowItem Circle::Ruleable Circle::Configurable );

use constant NETTYPE => 'raw';

use base qw( Circle::Rule::Store ); # for the attributes

use Text::Balanced qw( extract_delimited );

use Circle::TaggedString;

use Circle::Widget::Box;
use Circle::Widget::Label;

sub new
{
   my $class = shift;
   my %args = @_;

   my $self = $class->SUPER::new( %args );

   $self->{loop} = $args{loop};
   $self->{root} = $args{root};

   $self->set_prop_tag( $args{tag} );

   $self->{host} = undef;
   $self->{port} = undef;
   $self->{echo} = 1;

   my $rulestore = $self->init_rulestore( parent => $args{root}->{rulestore} );

   $rulestore->register_action( "sendline" => $self );

   $rulestore->new_chain( "input" );
   $rulestore->new_chain( "connected" );

   return $self;
}

sub describe
{
   my $self = shift;
   return __PACKAGE__."[" . $self->get_prop_tag . "]";
}

sub parse_action_sendline
   : Rule_description("Send a line of text to the peer")
   : Rule_format('$text')
{
   my $self = shift;
   my ( $spec ) = @_;

   my $text = extract_delimited( $spec, q{"} );
   
   # Trim leading and trailing "
   s/^"//, s/"$// for $text;

   # Unescape intermediate \\ and \"
   $text =~ s/\\([\\"])/$1/g;

   return $text;
}

sub deparse_action_sendline
{
   my $self = shift;
   my ( $text ) = @_;

   $text =~ s/([\\"])/\\$1/g;
   return qq{"$text"};
}

sub eval_action_sendline
{
   my $self = shift;
   my ( $event, $results, $text ) = @_;

   if( my $conn = $self->{conn} ) {
      $conn->write( "$text\r\n" );
   }
}

sub command_connect
   : Command_description("Connect to the server")
   : Command_arg('host?')
   : Command_arg('port?')
{
   my $self = shift;
   my ( $host, $port, $cinv ) = @_;

   $host ||= $self->{host};
   $port ||= $self->{port}; # 0 is not a valid TCP port

   defined $host or return $cinv->responderr( "Cannot connect - no host defined" );
   defined $port or return $cinv->responderr( "Cannot connect - no port defined" );

   my $loop = $self->{loop};
   $loop->connect(
      host    => $host,
      service => $port,

      on_connected => sub {
         my ( $sock ) = @_;

         $cinv->respond( "Connected to $host:$port", level => 1 );

         my $conn = $self->{conn} = IO::Async::Stream->new(
            handle => $sock,
            on_read => sub {
               my ( undef, $buffref, $closed ) = @_;
               return 0 unless $$buffref =~ s/^([^\r\n]*)\r?\n//;

               $self->incoming_text( $1 );

               return 1;
            },

            on_closed => sub {
               $self->push_displayevent( "status", { text => "Connection closed by peer" } );

               $self->set_prop_connected(0);
               $self->fire_event( "disconnected" );
               undef $self->{conn};
            },
         );

         $loop->add( $conn );

         $self->run_rulechain( "connected" );

         $self->set_prop_connected(1);
         $self->fire_event( "connected" );
      },

      on_resolve_error => sub {
         $cinv->responderr( "Unable to resolve $host:$port - $_[0]", level => 3 );
      },

      on_connect_error => sub {
         $cinv->responderr( "Unable to connect to $host:$port", level => 3 );
      },
   );

   return;
}

sub command_discon
   : Command_description( "Disconnect TCP port" )
{
   my $self = shift;
   my ( $cinv ) = @_;

   if( my $conn = $self->{conn} ) {
      $conn->close;
      undef $self->{conn};

      $cinv->respond( "Disconnected", level => 1 );
   }
   else {
      $cinv->responderr( "Not connected" );
   }

   return;
}

sub command_close
   : Command_description("Disconnect and close the window")
{
   my $self = shift;

   if( my $conn = $self->{conn} ) {
      $conn->close;
      undef $self->{conn};
   }

   $self->destroy;
}

sub do_send
{
   my $self = shift;
   my ( $text ) = @_;

   # TODO: Line separator

   if( my $conn = $self->{conn} ) {
      $conn->write( "$text\r\n" );

      $self->push_displayevent( "text", { text => $text } ) if $self->{echo};
   }
   else {
      $self->responderr( "Not connected" );
   }
}

sub enter_text
{
   my $self = shift;
   my ( $text ) = @_;

   $self->do_send( $text );
}

sub command_send
   : Command_description('Send a line of text')
   : Command_arg('text', eatall => 1)
{
   my $self = shift;
   my ( $text, $cinv ) = @_;

   $self->do_send( $text );
}

sub incoming_text
{
   my $self = shift;
   my ( $text ) = @_;

   my $event = {
      text  => Circle::TaggedString->new( $text ),
      level => 2,
   };

   $self->run_rulechain( "input", $event );

   $self->push_displayevent( "text", { text => $event->{text} } );
   $self->bump_level( $event->{level} ) if defined $event->{level};
}

sub commandable_parent
{
   my $self = shift;
   return $self->{root};
}

sub enumerable_name
{
   my $self = shift;
   return $self->get_prop_tag;
}

sub enumerable_parent
{
   my $self = shift;
   return $self->{root};
}

### Settings

sub setting_host
   : Setting_description("Hostname of the server")
   : Setting_type('str')
{
   my $self = shift;
   my ( $newvalue ) = @_;

   $self->{host} = $newvalue if defined $newvalue;
   return $self->{host};
}

sub setting_port
   : Setting_description("Port number of the server")
   : Setting_type('int')
{
   my $self = shift;
   my ( $newvalue ) = @_;

   $self->{port} = $newvalue if defined $newvalue;
   return $self->{port};
}

sub setting_echo
   : Setting_description("Local line echo")
   : Setting_type('bool')
{
   my $self = shift;
   my ( $newvalue ) = @_;

   $self->{echo} = $newvalue if defined $newvalue;
   return $self->{echo};
}

sub load_configuration
{
   my $self = shift;
   my ( $ynode ) = @_;

   $self->load_settings( $ynode, qw( host port echo ) );

   $self->load_rules_configuration( $ynode );
}

sub store_configuration
{
   my $self = shift;
   my ( $ynode ) = @_;

   $self->store_settings( $ynode, qw( host port echo ) );

   $self->store_rules_configuration( $ynode );
}

###
# Widgets
###

sub get_widget_statusbar
{
   my $self = shift;

   my $registry = $self->{registry};

   my $statusbar = $registry->construct(
      "Circle::Widget::Box",
      orientation => "horizontal",
   );

   my $serverlabel = $registry->construct(
      "Circle::Widget::Label",
   );
   $self->watch_property( "connected", 
      on_updated => sub {
         my ( $self, $connected ) = @_;
         $connected ? $serverlabel->set_prop_text( $self->{host} . ":" . $self->{port} )
                    : $serverlabel->set_prop_text( "--unconnected--" );
      }
   );

   $statusbar->add( $serverlabel );

   return $statusbar;
}

1;
