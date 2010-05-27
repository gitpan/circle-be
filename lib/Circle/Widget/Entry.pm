#  You may distribute under the terms of the GNU General Public License
#
#  (C) Paul Evans, 2008-2010 -- leonerd@leonerd.org.uk

package Circle::Widget::Entry;

use strict;

use base qw( Circle::Widget );

use Tangence::Constants;

our %METHODS = (
   enter => {
      args => [qw( str )],
      ret  => '',
   },
);

our %PROPS = (
   autoclear => {
      dim  => DIM_SCALAR,
      type => 'bool',
      smash => 1,
   },
   text => {
      dim  => DIM_SCALAR,
      type => 'str',
   },

   history => {
      dim  => DIM_QUEUE,
      type => 'str',
   },
);

sub new
{
   my $class = shift;
   my %args = @_;

   my $self = $class->SUPER::new( @_ );

   $self->{on_enter} = $args{on_enter};
   $self->{history}  = $args{history};

   $self->set_prop_autoclear( $args{autoclear} );

   return $self;
}

sub method_enter
{
   my $self = shift;
   my ( $ctx, $text ) = @_;
   $self->{on_enter}->( $text, $ctx );

   if( defined( my $history = $self->{history} ) ) {
      my $histqueue = $self->get_prop_history;

      my $overcount = @$histqueue + 1 - $history;

      $self->shift_prop_history( $overcount ) if $overcount > 0;

      $self->push_prop_history( $text );
   }
}

1;
