#  You may distribute under the terms of the GNU General Public License
#
#  (C) Paul Evans, 2008-2010 -- leonerd@leonerd.org.uk

package Circle::CommandInvocation;

use strict;
use warnings;

sub new
{
   my $class = shift;
   my ( $text, $connection, $invocant ) = @_;

   $text =~ s/^\s+//;

   return bless [ $text, $connection, $invocant ], $class;
}

sub nest
{
   my $self = shift;
   my ( $text ) = @_;
   return (ref $self)->new( $text, $self->connection, $self->invocant );
}

sub connection
{
   my $self = shift;
   return $self->[1];
}

sub invocant
{
   my $self = shift;
   return $self->[2];
}

sub peek_token
{
   my $self = shift;

   if( $self->[0] =~ m/^"/ ) {
      $self->[0] =~ m/^"(.*)"/ and return $1;
   }
   else {
      $self->[0] =~ m/^(\S+)/ and return $1;
   }

   return undef;
}

sub pull_token
{
   my $self = shift;

   if( $self->[0] =~ m/^"/ ) {
      $self->[0] =~ s/^"(.*)"\s*// and return $1;
   }
   else {
      $self->[0] =~ s/^(\S+)\s*// and return $1;
   }

   return undef;
}

sub peek_remaining
{
   my $self = shift;
   return $self->[0];
}

# delegate these to invocant
foreach my $method (qw(
   respond
   responderr
   respond_table
)) {
   no strict 'refs';
   *$method = sub { shift->invocant->$method( @_ ) };
}

1;
