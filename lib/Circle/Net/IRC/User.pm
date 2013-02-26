#  You may distribute under the terms of the GNU General Public License
#
#  (C) Paul Evans, 2008-2013 -- leonerd@leonerd.org.uk

package Circle::Net::IRC::User;

use strict;
use warnings;
use base qw( Circle::Net::IRC::Target );

use Carp;

# Don't reprint RPL_USERISAWAY message within 1 hour
# TODO: Some sort of config setting system
my $awaytime_print = 3600;

sub default_message_level
{
   my $self = shift;
   my ( $hints ) = @_;

   return 3;
}

sub on_message
{
   my $self = shift;
   my ( $command, $message, $hints ) = @_;

   # Numerics come from the server; real commands come from the user
   if( $command !~ m/^(\d+)$/ ) {
      my $ident    = $hints->{prefix_user};
      my $hostname = $hints->{prefix_host};

      $self->update_ident( "$ident\@$hostname" );
   }

   return $self->SUPER::on_message( @_ );
}

sub update_ident
{
   my $self = shift;
   my ( $ident ) = @_;

   return if $self->get_prop_ident eq $ident;
   $self->set_prop_ident( $ident );
}

sub on_message_NICK
{
   my $self = shift;
   my ( $message, $hints ) = @_;

   my $oldnick = $self->name;
   my $newnick = $hints->{new_nick};

   $self->push_displayevent( "irc.nick", { oldnick => $oldnick, newnick => $newnick } );
   $self->bump_level( 1 );

   $self->set_prop_name( $newnick );
   $self->set_prop_tag( $newnick );

   my $oldnick_folded = $self->{irc}->casefold_name( $oldnick );

   $self->fire_event( "change_nick", $oldnick, $oldnick_folded, $newnick, $hints->{new_nick_folded} );

   return 1;
}

sub on_message_QUIT
{
   my $self = shift;
   my ( $message, $hints ) = @_;

   my $nick    = $self->name;
   my $quitmsg = $hints->{text};

   defined $quitmsg or $quitmsg = "";

   my $net = $self->{net};
   my $quitmsg_formatted = $net->format_text( $quitmsg );

   my $userhost = "$hints->{prefix_user}\@$hints->{prefix_host}";

   $self->push_displayevent( "irc.quit", { nick => $nick, userhost => $userhost, quitmsg => $quitmsg_formatted } );
   $self->bump_level( 1 );

   return 1;
}

sub on_message_301 # RPL_AWAY
{
   my $self = shift;
   my ( $message, $hints ) = @_;

   my $nick    = $self->name;
   my $awaymsg = $hints->{text};

   defined $awaymsg or $awaymsg = "";

   # Surpress the message if it's already been printed and it's quite soon
   my $now = time;
   if( defined $self->{printed_awaymsg} and
       $self->{printed_awaymsg} eq $awaymsg and
       $now < $self->{printed_awaytime} + $awaytime_print ) {
      return 1;
   }

   my $net = $self->{net};
   my $awaymsg_formatted = $net->format_text( $awaymsg );

   my $userhost = "$hints->{prefix_user}\@$hints->{prefix_host}";

   $self->push_displayevent( "irc.away", { nick => $nick, userhost => $userhost, text => $awaymsg_formatted } );
   $self->bump_level( 1 );

   $self->{printed_awaymsg} = $awaymsg;
   $self->{printed_awaytime} = $now;

   return 1;
}

sub command_close
   : Command_description("Close the window")
{
   my $self = shift;

   $self->destroy;
}

sub make_widget_pre_scroller
{
   my $self = shift;
   my ( $box ) = @_;

   my $registry = $self->{registry};

   my $identlabel = $registry->construct(
      "Circle::Widget::Label",
   );
   $self->watch_property( "ident",
      on_updated => sub { $identlabel->set_prop_text( $_[1] ) }
   );

   $box->add( $identlabel );
}

sub get_widget_statusbar
{
   my $self = shift;

   my $registry = $self->{registry};
   my $net = $self->{net};

   my $statusbar = $registry->construct(
      "Circle::Widget::Box",
      orientation => "horizontal",
   );

   $statusbar->add( $net->get_widget_netname );

   return $statusbar;
} 

0x55AA;
