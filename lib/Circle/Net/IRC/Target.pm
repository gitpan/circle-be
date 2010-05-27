#  You may distribute under the terms of the GNU General Public License
#
#  (C) Paul Evans, 2008-2010 -- leonerd@leonerd.org.uk

package Circle::Net::IRC::Target;

use strict;
use base qw( Tangence::Object Circle::WindowItem );

use Tangence::Constants;

our %METHODS = (
   msg => {
      args => [qw( str )],
      ret  => '',
   },
   notice => {
      args => [qw( str )],
      ret  => '',
   },
   act => {
      args => [qw( str )],
      ret  => '',
   },
);

our %EVENTS = (
   msg => {
      args => [qw( str str )],
   },
   notice => {
      args => [qw( str str )],
   },
   act => {
      args => [qw( str str )],
   }
);

our %PROPS = (
   name => {
      dim   => DIM_SCALAR,
      type  => 'str',
      smash => 1,
   },

   network => {
      dim   => DIM_SCALAR,
      type  => 'obj',
      smash => 1,
   },

   real => {
      dim   => DIM_SCALAR,
      type  => 'bool',
   },
);

sub new
{
   my $class = shift;
   my %args = @_;

   my $self = $class->SUPER::new( @_ );

   $self->{irc} = $args{irc};

   $self->set_prop_name( $args{name} );
   $self->set_prop_tag( $args{name} );

   $self->{net} = $args{net};

   return $self;
}

# Convenience accessor
sub name
{
   my $self = shift;
   return $self->get_prop_name;
}

sub describe
{
   my $self = shift;
   return ref($self) . "[" . $self->name . "]";
}

sub get_prop_tag
{
   my $self = shift;
   return $self->name;
}

sub get_prop_network
{
   my $self = shift;
   return $self->{net};
}

sub reify
{
   my $self = shift;

   return if $self->get_prop_real;

   $self->set_prop_real( 1 );

   my $root = $self->{net}->{root};
   $root->broadcast_sessions( "new_item", $self );
}

sub on_message
{
   my $self = shift;
   my ( $command, $message, $hints ) = @_;

   # $command might contain spaces from synthesized events - e.g. "ctcp ACTION"
   ( my $method = "on_message_$command" ) =~ s/ /_/g;

   return 1 if $self->can( $method ) and $self->$method( $message, $hints );

   if( not $hints->{handled} and not $hints->{synthesized} ) {
      $self->push_displayevent( "irc.irc", {
            command => $command,
            prefix  => $message->prefix,
            args    => join( " ", map { "'$_'" } $message->args ),
         } );
      $self->bump_level( 1 );
   }

   return 1;
}

sub pick_display_target
{
   my $self = shift;
   my ( $display ) = @_;

   return $self        if $display eq "self";
   return $self->{net} if $display eq "server";
}

sub on_message_text
{
   my $self = shift;
   my ( $message, $hints ) = @_;

   my $srcnick = $hints->{prefix_name};
   my $text    = $hints->{text};

   my $is_notice = $hints->{is_notice};

   my $net = $self->{net};

   my $event = {
      %$hints,
      text  => $net->format_text_tagged( $text ),
      level => $is_notice ? 1 : 2,
      display => ( !defined $hints->{prefix_nick} or $is_notice && !$self->get_prop_real ) ? "server" : "self",
   };

   $net->run_rulechain( "input", $event );

   my $eventname = $is_notice ? "notice" : "msg";

   $self->fire_event( $eventname, $srcnick, $text );

   if( my $target = $self->pick_display_target( $event->{display} ) ) {
      $target->push_displayevent( "irc.$eventname", { target => $self->name, nick => $srcnick, text => $event->{text} } );
      $target->bump_level( $event->{level} ) if defined $event->{level};

      $target->reify;
   }

   return 1;
}

sub on_message_ctcp_ACTION
{
   my $self = shift;
   my ( $message, $hints ) = @_;

   my $srcnick = $hints->{prefix_name};
   my $text    = $hints->{ctcp_args};

   my $net = $self->{net};

   my $event = {
      %$hints,
      text  => $net->format_text_tagged( $text ),
      level => 2,
      display => "self",
   };

   $net->run_rulechain( "input", $event );

   $self->fire_event( "act", $srcnick, $text );

   if( my $target = $self->pick_display_target( $event->{display} ) ) {
      $target->push_displayevent( "irc.act", { target => $self->name, nick => $srcnick, text => $event->{text} } );
      $target->bump_level( $event->{level} ) if defined $event->{level};

      $target->reify;
   }

   return 1;
}

sub on_connected
{
   my $self = shift;

   $self->push_displayevent( "status", { text => "Server is connected" } );
}

sub on_disconnected
{
   my $self = shift;

   $self->push_displayevent( "status", { text => "Server is disconected" } );
}

sub msg
{
   my $self = shift;
   my ( $text ) = @_;

   my @lines = split( m/\n/, $text );

   my $irc = $self->{irc};
   my $net = $self->{net};

   foreach my $line ( @lines ) {
      $irc->send_message( "PRIVMSG", undef, $self->name, $line );

      my $line_formatted = $net->format_text( $line );

      $self->fire_event( "msg", $irc->nick, $line );
      $self->push_displayevent( "irc.msg", { target => $self->name, nick => $irc->nick, text => $line_formatted } );
   }
}

sub method_msg
{
   my $self = shift; my $ctx = shift;
   $self->msg( @_ );
}

sub notice
{
   my $self = shift;
   my ( $text ) = @_;

   my $irc = $self->{irc};
   $irc->send_message( "NOTICE", undef, $self->name, $text );

   my $net = $self->{net};
   my $text_formatted = $net->format_text( $text );

   $self->fire_event( "notice", $irc->nick, $text );
   $self->push_displayevent( "irc.notice", { target => $self->name, nick => $irc->nick, text => $text_formatted } );
}

sub method_notice
{
   my $self = shift; my $ctx = shift;
   $self->notice( @_ );
}

sub act
{
   my $self = shift;
   my ( $text ) = @_;

   my $irc = $self->{irc};
   $irc->send_ctcp( undef, $self->name, "ACTION", $text );

   my $net = $self->{net};
   my $text_formatted = $net->format_text( $text );

   $self->fire_event( "act", $irc->nick, $text );
   $self->push_displayevent( "irc.act", { target => $self->name, nick => $irc->nick, text => $text_formatted } );
}

sub method_act
{
   my $self = shift; my $ctx = shift;
   $self->act( @_ );
}

sub command_say
   : Command_description("Quote text directly as a PRIVMSG")
   : Command_arg('text', eatall => 1)
{
   my $self = shift;
   my ( $text ) = @_;

   $self->msg( $text );

   return;
}

sub command_me
   : Command_description("Send a CTCP ACTION")
   : Command_arg('text', eatall => 1)
{
   my $self = shift;
   my ( $text ) = @_;

   $self->act( $text );

   return;
}

sub commandable_parent
{
   my $self = shift;
   return $self->{net};
}

sub enter_text
{
   my $self = shift;
   my ( $text ) = @_;

   return unless length $text;

   $self->msg( $text );
}

1;
