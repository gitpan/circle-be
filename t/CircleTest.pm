#  You may distribute under the terms of the GNU General Public License
#
#  (C) Paul Evans, 2012 -- leonerd@leonerd.org.uk

package t::CircleTest;

use strict;
use warnings;

our $VERSION = '0.04';

use Exporter qw( import );
our @EXPORT_OK = qw(
   get_widget_from
   get_widgetset_from
   send_command
);

use IO::Async::Test;

sub get_widget_from
{
   my ( $windowitem ) = @_;

   my $widget;
   $windowitem->call_method(
      method => "get_widget",
      on_result => sub { $widget = $_[0] },
      on_error  => sub { die "Test failed early - $_[-1]" },
   );

   wait_for { $widget };
   return $widget;
}

my %widgetsets;
sub get_widgetset_from
{
   my ( $windowitem ) = @_;

   return $widgetsets{$windowitem} if $widgetsets{$windowitem};

   my $widget = get_widget_from( $windowitem );

   my %widgets;
   my @queue = ( $widget );
   while( my $w = shift @queue ) {
      if( $w->proxy_isa( "Circle::Widget::Box" ) ) {
         push @queue, map { $_->{child} } @{ $w->prop( "children" ) };
      }
      else {
         $widgets{ ( $w->proxy_isa )[0] } = $w;
      }
   }

   return $widgetsets{$windowitem} = \%widgets;
}

sub send_command
{
   my ( $windowitem, $command ) = @_;

   my $widgetset = get_widgetset_from( $windowitem );

   my $entry = $widgetset->{"Circle::Widget::Entry"} or
      die "Expected $windowitem to have a Circle::Widget::Entry";

   my $done;
   $entry->call_method(
      method => "enter",
      args   => [ $command ],
      on_result => sub { $done = 1 },
      on_error  => sub { die "Test failed early - $_[-1]" },
   );

   wait_for { $done };
}

0x55AA;
