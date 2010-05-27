#  You may distribute under the terms of the GNU General Public License
#
#  (C) Paul Evans, 2008-2010 -- leonerd@leonerd.org.uk

package Circle::Widget::Scroller;

use strict;

use base qw( Circle::Widget );

use Tangence::Constants;

our %PROPS = (
   displayevents => {
      dim  => DIM_QUEUE,
      type => 'list(any)',
   },
);

sub new
{
   my $class = shift;
   my %args = @_;

   my $self = $class->SUPER::new( @_ );

   $self->{scrollback} = $args{scrollback};

   return $self;
}

sub push_event
{
   my $self = shift;
   my ( $event, $args )=  @_;

   my $eventqueue = $self->get_prop_displayevents;

   my $overcount = @$eventqueue + 1 - $self->{scrollback};

   $self->shift_prop_displayevents( $overcount ) if $overcount > 0;

   $self->push_prop_displayevents( [ $event, time(), $args ] );
}

1;
