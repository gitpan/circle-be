#  You may distribute under the terms of the GNU General Public License
#
#  (C) Paul Evans, 2008-2010 -- leonerd@leonerd.org.uk

package Circle::Net::IRC;

use strict;

use base qw( Tangence::Object Circle::WindowItem Circle::Ruleable Circle::Configurable );

use base qw( Circle::Rule::Store ); # for the attributes

use constant NETTYPE => 'irc';

use Circle::Net::IRC::Channel;
use Circle::Net::IRC::User;

use Circle::TaggedString;

use Circle::Rule::Store;

use Circle::Widget::Box;
use Circle::Widget::Label;

use Tangence::Constants;

use Net::Async::IRC;

use Text::Balanced qw( extract_delimited );

our %METHODS = (
   get_isupport => {
      args => [qw( str )],
      ret  => 'any',
   },
);

our %EVENTS = (
   connected => {
      args => [],
   },
   disconnected => {
      args => [],
   },
);

our %PROPS = (
   nick => {
      dim  => DIM_SCALAR,
      type => 'str',
   },

   away => {
      dim  => DIM_SCALAR,
      type => 'bool',
   },

   channels => {
      dim  => DIM_OBJSET,
      type => 'obj',
   },

   users => {
      dim  => DIM_OBJSET,
      type => 'obj',
   },
);

sub new
{
   my $class = shift;
   my %args = @_;

   my $self = $class->SUPER::new( %args );

   $self->{root} = $args{root};
   $self->{loop} = $args{loop};

   # For WindowItem
   $self->set_prop_tag( $args{tag} );

   $self->{irc} = Net::Async::IRC->new(
      on_message => sub {
         my ( $irc, $command, $message, $hints ) = @_;
         $self->on_message( $command, $message, $hints );
      },

      on_closed => sub {
         $self->on_closed;
      },

      encoding => "UTF-8",
   );

   $self->{servers} = [];

   $self->{channels} = {};
   $self->{users} = {};

   my $rulestore = $self->init_rulestore( parent => $args{root}->{rulestore} );

   $rulestore->register_cond( matchnick => $self );
   $rulestore->register_cond( fromnick  => $self );
   $rulestore->register_cond( channel   => $self );

   $rulestore->register_action( highlight => $self );
   $rulestore->register_action( display   => $self );

   $rulestore->new_chain( "input" );

   $rulestore->get_chain( "input" )->append_rule( "matchnick: highlight" );

   return $self;
}

sub describe
{
   my $self = shift;
   return __PACKAGE__."[". $self->get_prop_tag . "]";
}

sub get_prop_users
{
   my $self = shift;

   my $users = $self->{users};
   return [ values %$users ];
}

sub reify
{
   # always real; this is a no-op
}

sub get_channel_if_exists
{
   my $self = shift;
   my ( $channame ) = @_;

   my $irc = $self->{irc};
   my $channame_folded = $irc->casefold_name( $channame );

   return $self->{channels}->{$channame_folded};
}

sub get_channel_or_create
{
   my $self = shift;
   my ( $channame ) = @_;

   my $irc = $self->{irc};
   my $channame_folded = $irc->casefold_name( $channame );

   return $self->{channels}->{$channame_folded} if exists $self->{channels}->{$channame_folded};

   my $registry = $self->{registry};
   my $chanobj = $registry->construct(
      "Circle::Net::IRC::Channel",
      net => $self,
      irc => $irc,
      name => $channame,
   );

   my $root = $self->{root};

   $self->{channels}->{$channame_folded} = $chanobj;
   $chanobj->subscribe_event( destroy => sub {
      $root->broadcast_sessions( "delete_item", $chanobj );
      $self->del_prop_channels( $chanobj );
      delete $self->{channels}->{$channame_folded};
   } );

   $self->add_prop_channels( $chanobj );

   return $chanobj;
}

sub get_user_if_exists
{
   my $self = shift;
   my ( $nick ) = @_;

   my $irc = $self->{irc};
   my $nick_folded = $irc->casefold_name( $nick );

   return $self->{users}->{$nick_folded};
}

sub get_user_or_create
{
   my $self = shift;
   my ( $nick ) = @_;

   my $irc = $self->{irc};
   my $nick_folded = $irc->casefold_name( $nick );

   return $self->{users}->{$nick_folded} if exists $self->{users}->{$nick_folded};

   my $registry = $self->{registry};
   my $userobj = $registry->construct(
      "Circle::Net::IRC::User",
      net => $self,
      irc => $irc,
      name => $nick,
   );

   my $root = $self->{root};

   $self->{users}->{$nick_folded} = $userobj;

   $userobj->subscribe_event( destroy => sub {
      $root->broadcast_sessions( "delete_item", $userobj );
      $self->del_prop_users( $userobj );
      my $nick_folded = $irc->casefold_name( $userobj->get_prop_name );
      delete $self->{users}->{$nick_folded};
   } );

   $userobj->subscribe_event( change_nick => sub {
      my ( undef, undef, $oldnick, $oldnick_folded, $newnick, $newnick_folded ) = @_;
      $self->{users}->{$newnick_folded} = delete $self->{users}->{$oldnick_folded};
   } );

   $self->add_prop_users( $userobj );

   return $userobj;
}

sub get_target_if_exists
{
   my $self = shift;
   my ( $name ) = @_;

   my $irc = $self->{irc};
   my $type = $irc->classify_name( $name );

   if( $type eq "channel" ) {
      return $self->get_channel_if_exists( $name );
   }
   elsif( $type eq "user" ) {
      return $self->get_user_if_exists( $name );
   }
   else {
      return undef;
   }
}

sub connected
{
   my $self = shift;

   # Consider we're "connected" if the underlying IRC object is logged in
   my $irc = $self->{irc};
   return $irc->is_loggedin;
}

# Map mIRC's colours onto an approximation of ANSI terminal
my @irc_colour_map = (
   15, 0, 4, 2,    # white black blue green
   9, 1, 5, 3,     # red [brown=darkred] [purple=darkmagenta] [orange=darkyellow]
   11, 10, 6, 14,  # yellow lightgreen cyan lightcyan
   12, 13, 8, 7    # lightblue [pink=magenta] grey lightgrey
);

sub format_colour
{
   my $self = shift;
   my ( $colcode ) = @_;

   return $colcode if $colcode =~ m/^#[0-9a-f]{6}/i;
   return "#$1$1$2$2$3$3" if $colcode =~ m/^#([0-9a-f])([0-9a-f])([0-9a-f])/i;

   return sprintf( "ansi.col%02d", $irc_colour_map[$1] ) if $colcode =~ m/^(\d\d?)/ and defined $irc_colour_map[$1];

   return undef;
}

sub format_text_tagged
{
   my $self = shift;
   my ( $text ) = @_;

   # IRC [well, technically mIRC but other clients have adopted it] uses Ctrl
   # characters to toggle formatting
   #  ^B = bold
   #  ^U = underline
   #  ^_ = underline
   #  ^R = reverse or italic - we'll use italic
   #  ^O = reset
   #  ^C = colour; followed by a code
   #     ^C      = reset colours
   #     ^Cff    = foreground
   #     ^Cff,bb = background
   #
   # irssi uses the following
   #  ^D$$ = foreground/background, in chr('0'+$colour),
   #  ^Db  = underline
   #  ^Dc  = bold
   #  ^Dd  = reverse or italic - we'll use italic
   #  ^Dg  = reset colours
   #
   # As a side effect we'll also strip all the other Ctrl chars

   # We'll also look for "poor-man's" highlighting
   #   *bold*
   #   _underline_
   #   /italic/

   my $ret = Circle::TaggedString->new();

   my %format;

   while( length $text ) {
      if( $text =~ s/^([\x00-\x1f])// ) {
         my $ctrl = chr(ord($1)+0x40);

         if( $ctrl eq "B" ) {
            $format{b} ? delete $format{b} : ( $format{b} = 1 );
         }
         elsif( $ctrl eq "U" or $ctrl eq "_" ) {
            $format{u} ? delete $format{u} : ( $format{u} = 1 );
         }
         elsif( $ctrl eq "R" ) {
            $format{i} ? delete $format{i} : ( $format{i} = 1 );
         }
         elsif( $ctrl eq "O" ) {
            undef %format;
         }
         elsif( $ctrl eq "C" ) {
            my $colourre = qr/#[0-9a-f]{6}|#[0-9a-f]{3}|\d\d?/i;

            if( $text =~ s/^($colourre),($colourre)// ) {
               $format{fg} = $self->format_colour( $1 );
               $format{bg} = $self->format_colour( $2 );
            }
            elsif( $text =~ s/^($colourre)// ) {
               $format{fg} = $self->format_colour( $1 );
            }
            else {
               delete $format{fg};
               delete $format{bg};
            }
         }
         elsif( $ctrl eq "D" ) {
            if( $text =~ s/^b// ) { # underline
               $format{u} ? delete $format{u} : ( $format{u} = 1 );
            }
            elsif( $text =~ s/^c// ) { # bold
               $format{b} ? delete $format{b} : ( $format{b} = 1 );
            }
            elsif( $text =~ s/^d// ) { # revserse/italic
               $format{i} ? delete $format{i} : ( $format{i} = 1 );
            }
            elsif( $text =~ s/^g// ) {
               undef %format
            }
            else {
               $text =~ s/^(.)(.)//;
               my ( $fg, $bg ) = map { ord( $_ ) - ord('0') } ( $1, $2 );
               if( $fg > 0 ) {
                  $format{fg} = sprintf( "ansi.col%02d", $fg );
               }
               if( $bg > 0 ) {
                  $format{bg} = sprintf( "ansi.col%02d", $bg );
               }
            }
         }
         else {
            print STDERR "Unhandled Ctrl code ^$ctrl\n";
         }
      }
      else {
         $text =~ s/^([^\x00-\x1f]+)//;
         my $piece = $1;

         # Now scan this piece for the text-based ones
         while( length $piece ) {
            # Look behind/ahead asserts to ensure we don't capture e.g.
            # /usr/bin/perl by mistake
            if( $piece =~ s/^(.*?)(?<!\w)(([\*_\/])\w+\3)(?!\w)// ) {
               my ( $pre, $inner, $type ) = ( $1, $2, $3 );

               $ret->append_tagged( $pre, %format ) if length $pre;

               my %innerformat = %format;

               $type =~ tr{*_/}{bui};
               $innerformat{$type} = 1;

               $ret->append_tagged( $inner, %innerformat );
            }
            else {
               $ret->append_tagged( $piece, %format );
               $piece = "";
            }
         }
      }
   }

   return $ret;
}

sub format_text
{
   my $self = shift;
   my ( $text ) = @_;

   return $self->format_text_tagged( $text );
}

###
# Rule subs
###

sub parse_cond_matchnick
   : Rule_description("Look for my IRC nick in the text")
   : Rule_format('')
{
   my $self = shift;
   return;
}

sub deparse_cond_matchnick
{
   my $self = shift;
   return;
}

sub eval_cond_matchnick
{
   my $self = shift;
   my ( $event, $results ) = @_;

   my $text = $event->{text}->str;

   my $nick = $self->{irc}->nick;

   pos( $text ) = 0;

   my $matched;

   while( $text =~ m/(\Q$nick\E)/gi ) {
      my ( $start, $end ) = ( $-[0], $+[0] );
      my $len = $end - $start;

      $results->push_result( "matchgroups", [ [ $start, $len ] ] );
      $matched = 1;
   }

   return $matched;
}

sub parse_cond_fromnick
   : Rule_description("Match the message originating nick against a regexp or string")
   : Rule_format('/regexp/ or "literal"')
{
   my $self = shift;
   my ( $spec ) = @_;

   if( $spec =~ m/^"/ ) {
      # Literal
      my $nick = extract_delimited( $spec, q{"} );
      s/^"//, s/"$// for $nick;

      return literal => $nick;
   }
   elsif( $spec =~ m{^/} ) {
      # Regexp
      my $re = extract_delimited( $spec, q{/} );
      s{^/}{}, s{/$}{} for $re;

      my $iflag = 1 if $spec =~ s/^i//;

      return re => qr/$re/i if $iflag;
      return re => qr/$re/;
   }
}

sub deparse_cond_fromnick
{
   my $self = shift;
   my ( $type, $pattern ) = @_;

   if( $type eq "literal" ) {
      return qq{"$pattern"};
   }
   elsif( $type eq "re" ) {
      # Perl tries to put (?-ixsm:RE) around our pattern. Lets attempt to remove
      # it if we can
      return "/$1/"  if $pattern =~ m/^\(\?-xism:(.*)\)$/;
      return "/$1/i" if $pattern =~ m/^\(\?i-xsm:(.*)\)$/;

      # Failed. Lets just be safe then
      return "/$pattern/";
   }
}

sub eval_cond_fromnick
{
   my $self = shift;
   my ( $event, $results, $type, $pattern ) = @_;

   my $src = $event->{prefix_name_folded};

   if( $type eq "literal" ) {
      my $irc = $self->{irc};

      return $src eq $irc->casefold_name( $pattern );
   }
   elsif( $type eq "re" ) {
      return $src =~ $pattern;
   }
}

sub parse_cond_channel
   : Rule_description("Event comes from a (named) channel")
   : Rule_format('"name"?')
{
   my $self = shift;
   my ( $spec ) = @_;

   if( $spec =~ m/^"/ ) {
      my $name = extract_delimited( $spec, q{"} );
      s/^"//, s/"$// for $name;

      return $name;
   }

   return undef;
}

sub deparse_cond_channel
{
   my $self = shift;
   my ( $name ) = @_;

   return qq{"$name"} if defined $name;
   return;
}

sub eval_cond_channel
{
   my $self = shift;
   my ( $event, $results, $name ) = @_;

   return 0 unless $event->{target_type}||"" eq "channel";

   return 1 unless defined $name;

   my $irc = $self->{irc};
   return $event->{target_name_folded} eq $irc->casefold_name( $name );
}

sub parse_action_highlight
   : Rule_description("Highlight matched regions and set activity level to 3")
   : Rule_format('')
{
   my $self = shift;
   return;
}

sub deparse_action_highlight
{
   my $self = shift;
   return;
}

sub eval_action_highlight
{
   my $self = shift;
   my ( $event, $results ) = @_;

   my $str = $event->{text};

   foreach my $matchgroup ( @{ $results->get_result( "matchgroups" ) } ) {
      my ( $start, $len ) = @{$matchgroup->[0]}[0,1];

      $str->apply_tag( $start, $len, b => 1 );
      $str->apply_tag( $start, $len, fg => "highlight" );
   }

   $event->{level} = 3;
}

sub parse_action_display
   : Rule_description("Set the display window to display an event")
   : Rule_format('self|server')
{
   my $self = shift;
   my ( $spec ) = @_;

   if( $spec eq "self" ) {
      return "self";
   }
   elsif( $spec eq "server" ) {
      return "server";
   }
   else {
      die "Unrecognised display spec\n";
   }
}

sub deparse_action_display
{
   my $self = shift;
   my ( $display ) = @_;

   return $display;
}

sub eval_action_display
{
   my $self = shift;
   my ( $event, $results, $display ) = @_;

   $event->{display} = $display;
}

###
# IRC message handlers
###

sub on_message
{
   my $self = shift;
   my ( $command, $message, $hints ) = @_;

   if( defined $hints->{target_name} ) {
      my $target;

      if( $hints->{target_type} eq "channel" ) {
         $target = $self->get_channel_or_create( $hints->{target_name} );
      }
      elsif( $hints->{target_is_me} and 
             defined $hints->{prefix_name} and
             not $hints->{prefix_is_me} ) {
         # Handle PRIVMSG and similar from the user
         $target = $self->get_user_or_create( $hints->{prefix_name} );
      }
      elsif( $hints->{target_type} eq "user" ) {
         # Handle numerics about the user - Net::Async::IRC has filled in the target
         $target = $self->get_user_or_create( $hints->{target_name} );
      }

      if( $target ) {
         return 1 if $target->on_message( $command, $message, $hints );
      }
   }
   elsif( grep { $command eq $_ } qw( NICK QUIT ) ) {
      # Target all of them
      my $handled = 0;

      my $method = "on_message_$command";

      $handled = 1 if $self->can( $method ) and $self->$method( $message, $hints );

      foreach my $target ( values %{ $self->{channels} } ) {
         $handled = 1 if $target->$method( $message, $hints );
      }

      my $nick_folded = $hints->{prefix_nick_folded};

      if( my $userobj = $self->get_user_if_exists( $hints->{prefix_nick} ) ) {
         $handled = 1 if $userobj->$method( $message, $hints );
      }

      return 1 if $handled;
   }
   elsif( $self->can( "on_message_$command" ) ) {
      my $method = "on_message_$command";
      my $handled = $self->$method( $message, $hints );

      return 1 if $handled;
   }

   if( not $hints->{handled} and not $hints->{synthesized} ) {
      $self->push_displayevent( "irc.irc", {
            command => $command,
            prefix  => $message->prefix,
            args    => join( " ", map { "'$_'" } $message->args ),
         } );
      $self->bump_level( 1 );
   }
}

sub on_message_NICK
{
   my $self = shift;
   my ( $message, $hints ) = @_;

   if( $hints->{prefix_is_me} ) {
      $self->set_prop_nick( $hints->{new_nick} );
   }

   return 1;
}

sub on_message_motd
{
   my $self = shift;
   my ( $message, $hints ) = @_;

   my $motd = $hints->{motd};
   $self->push_displayevent( "irc.motd", { text => $self->format_text($_) } ) for @$motd;
   $self->bump_level( 1 );

   return 1;
}

sub on_message_305
{
   my $self = shift;
   my ( $message, $hints ) = @_;

   $self->set_prop_away( 0 );

   $self->push_displayevent( "irc.text", { server => $hints->{prefix_host}, text => $hints->{text} } );
   $self->bump_level( 1 );

   return 1;
}

sub on_message_306
{
   my $self = shift;
   my ( $message, $hints ) = @_;

   $self->set_prop_away( 1 );

   $self->push_displayevent( "irc.text", { server => $hints->{prefix_host}, text => $hints->{text} } );
   $self->bump_level( 1 );

   return 1;
}

sub on_closed
{
   my $self = shift;

   $self->push_displayevent( "status", { text => "Server is disconected" } );

   foreach my $target ( values %{ $self->{channels} }, values %{ $self->{users} } ) {
      $target->on_disconnected;
   }

   $self->fire_event( "disconnected" );
}

sub method_get_isupport
{
   my $self = shift;
   my ( $ctx, $key ) = @_;

   my $irc = $self->{irc};
   return $irc->isupport( $key );
}

use Circle::Collection
   name  => 'servers',
   storage => 'array',
   attrs => [
      host  => { desc => "hostname" },
      port  => { desc => "alternative port",
                 show => sub { $_ || "6667" },
               },
      ident => { desc => "alternative ident",
                 show => sub { $_ || '$USER' },
               },
      pass  => { desc => "connection password",
                 show => sub { $_ ? "set" : "" },
               },
   ],
   ;

sub command_nick
   : Command_description("Change nick")
   : Command_arg('nick?')
{
   my $self = shift;
   my ( $newnick ) = @_;

   my $irc = $self->{irc};

   if( defined $newnick ) {
      $irc->change_nick( $newnick );
   }

   return ( "Nick: " . $irc->nick );
}

sub command_connect
   : Command_description("Connect to an IRC server")
   : Command_arg('host?')
   : Command_opt('port=$',  desc => "alternative port (default '6667')")
   : Command_opt('nick=$',  desc => "initial nick")
   : Command_opt('ident=$', desc => "alternative ident (default '\$USER')")
   : Command_opt('pass=$',  desc => "connection password")
{
   my $self = shift;
   my ( $host, $opts, $cinv ) = @_;

   my $s;

   if( !defined $host ) {
      if( !@{ $self->{servers} } ) {
         $cinv->responderr( "Cannot connect - no servers defined" );
         return;
      }

      # TODO: Pick one - for now just the first
      $s = $self->{servers}->[0];

      $host = $s->{host};
   }
   else {
      ( $s ) = grep { $_->{host} eq $host } @{ $self->{servers} };
   }

   my $irc = $self->{irc};

   my $loop = $self->{loop};
   $loop->add( $irc );

   my $nick = $opts->{nick} || $self->get_prop_nick;

   $irc->login( 
      host    => $host,
      service => $opts->{port}  || $s->{port},
      nick    => $nick,
      user    => $opts->{ident} || $s->{ident},
      pass    => $opts->{pass}  || $s->{pass},

      on_login => sub {
         $cinv->respond( "Connected to $host", level => 1 );

         foreach my $target ( values %{ $self->{channels} }, values %{ $self->{users} } ) {
            $target->on_connected;
         }

         $self->fire_event( "connected" );
      },

      on_error => sub {
         $cinv->responderr( "Unable to connect to $host - $_[0]", level => 3 );
         $loop->remove( $irc );
      },
   );

   return ( "Connecting to $host ..." );
}

sub command_disconnect
   : Command_description("Disconnect from the IRC server")
{
   my $self = shift;

   my $irc = $self->{irc};
   $irc->close;
}

sub command_join
   : Command_description("Join a channel")
   : Command_arg('channel')
{
   my $self = shift;
   my ( $channel, $cinv ) = @_;

   my $irc = $self->{irc};

   my $chanobj = $self->get_channel_or_create( $channel );

   $chanobj->reify;

   $chanobj->join(
      on_joined => sub {
         $cinv->respond( "Joined $channel", level => 1 );
      },
      on_join_error => sub {
         $cinv->responderr( "Cannot join $channel - $_[0]", level => 3 );
      },
   );

   return;
}

sub command_part
   : Command_description("Part a channel")
   : Command_arg('channel')
   : Command_arg('message?', eatall => 1)
{
   my $self = shift;
   my ( $channel, $message, $cinv ) = @_;

   my $chanobj = $self->get_channel_if_exists( $channel )
      or return "No such channel $channel";

   $chanobj->part(
      message => $message,

      on_parted => sub {
         $cinv->respond( "Parted $channel", level => 1 );
         $chanobj->destroy;
      },
      on_part_error => sub {
         $cinv->respond( "Cannot part $channel - $_[0]", level => 3 );
      },
   );

   return;
}

sub command_query
   : Command_description("Open a private message window to a user")
   : Command_arg('nick')
{
   my $self = shift;
   my ( $nick, $cinv ) = @_;

   my $userobj = $self->get_user_or_create( $nick );

   $userobj->reify;

   # TODO: Focus it

   return;
}

sub command_msg
   : Command_description("Send a PRIVMSG to a target")
   : Command_arg('target')
   : Command_arg('text', eatall => 1)
{
   my $self = shift;
   my ( $target, $text ) = @_;

   if( my $targetobj = $self->get_target_if_exists( $target ) ) {
      $targetobj->msg( $text );
   }
   else {
      my $irc = $self->{irc};
      $irc->send_message( "PRIVMSG", undef, $target, $text );
   }

   return;
}

sub command_notice
   : Command_description("Send a NOTICE to a target")
   : Command_arg('target')
   : Command_arg('text', eatall => 1)
{
   my $self = shift;
   my ( $target, $text ) = @_;

   if( my $targetobj = $self->get_target_if_exists( $target ) ) {
      $targetobj->notice( $text );
   }
   else {
      my $irc = $self->{irc};
      $irc->send_message( "NOTICE", undef, $target, $text );
   }

   return;
}

sub command_quote
   : Command_description("Send a raw IRC command")
   : Command_arg('cmd')
   : Command_arg('args', collect => 1)
{
   my $self = shift;
   my ( $cmd, $args ) = @_;

   my $irc = $self->{irc};

   $irc->send_message( $cmd, undef, @$args );

   return;
}

sub command_away
   : Command_description("Set AWAY message")
   : Command_arg('message', eatall => 1)
{
   my $self = shift;
   my ( $message ) = @_;

   my $irc = $self->{irc};

   length $message or $message = "away";

   $irc->send_message( "AWAY", undef, $message );

   return;
}

sub command_unaway
   : Command_description("Remove AWAY message")
{
   my $self = shift;

   my $irc = $self->{irc};

   $irc->send_message( "AWAY", undef );

   return;
}

sub command_channels
   : Command_description("Display or manipulate channels")
{
}

sub command_channels_list
   : Command_description("List the channels")
   : Command_subof('channels')
   : Command_default()
{
   my $self = shift;
   my ( $cinv ) = @_;

   my $channels = $self->{channels};

   my @table;

   foreach my $channame ( sort keys %$channels ) {
      my $chan = $channels->{$channame};
      push @table, [
         $chan->get_prop_name,
         $chan->{state} == Circle::Net::IRC::Channel::STATE_JOINED ? "yes" : "no",
      ];
   }

   $cinv->respond_table( \@table, headings => [qw( name joined )] );
   return;
}

sub commandable_parent
{
   my $self = shift;
   return $self->{root};
}

sub enumerate_items
{
   my $self = shift;

   my %all = ( %{ $self->{channels} }, %{ $self->{users} } );

   # Filter only the real ones
   $all{$_}->get_prop_real or delete $all{$_} for keys %all;

   return \%all;
}

sub setting_nick
   : Setting_description("Initial connection nick")
   : Setting_type('str')
{
   my $self = shift;
   my ( $newvalue ) = @_;

   $self->set_prop_nick( $newvalue ) if defined $newvalue;
   return $self->get_prop_nick;
}

sub load_configuration
{
   my $self = shift;
   my ( $ynode ) = @_;

   $self->load_settings( $ynode, qw( nick ) );

   $self->load_servers_configuration( $ynode );

   $self->load_rules_configuration( $ynode );
}

sub store_configuration
{
   my $self = shift;
   my ( $ynode ) = @_;

   $self->store_settings( $ynode, qw( nick ) );

   $self->store_servers_configuration( $ynode );

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

   my $nicklabel = $registry->construct(
      "Circle::Widget::Label",
   );
   $self->watch_property( "nick", on_updated => sub { $nicklabel->set_prop_text( $_[0] ) } );

   $statusbar->add( $nicklabel );

   my $awaylabel = $registry->construct(
      "Circle::Widget::Label",
   );
   $self->watch_property( "away", on_updated => sub { $awaylabel->set_prop_text( $_[0] ? "[AWAY]" : "" ) } );

   $statusbar->add( $awaylabel );

   return $statusbar;
}

1;
