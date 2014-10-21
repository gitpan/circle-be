#  You may distribute under the terms of the GNU General Public License
#
#  (C) Paul Evans, 2008-2010 -- leonerd@leonerd.org.uk

package Circle::GlobalRules;

use strict;
use warnings;

use Text::Balanced qw( extract_delimited );

use base qw( Circle::Rule::Store ); # for the attributes

# Not an object class. Instead, just a store of rule subs

sub register
{
   my ( $rulestore ) = @_;

   $rulestore->register_cond( matches => __PACKAGE__ );

   $rulestore->register_action( format => __PACKAGE__ );
   $rulestore->register_action( unformat => __PACKAGE__ );
   $rulestore->register_action( level => __PACKAGE__ );
}

###### CONDITIONS

### MATCHES

sub parse_cond_matches
   : Rule_description("Look for regexp or substring matches in the text")
   : Rule_format('/regexp/ or "literal"')
{
   shift; # class
   my ( $spec ) = @_;

   if( $spec =~ m{^/} ) {
      # Try to pull the flags
      my ( $content, $flags ) = $spec =~ m{^/(.*)/([i]*)$} or die "Unrecognised regexp string $spec\n";

      return qr/$content/i if $flags eq "i";
      return qr/$content/;
   }
   elsif( $spec =~ m{^"} ) {
      my ( $content ) = $spec =~ m{^"(.*)"$} or die "Unrecognised literal string $spec\n";

      return qr/\Q$content/;
   }
   else {
      die "Unrecognised string type $spec";
   }
}

sub deparse_cond_matches
{
   shift; # class
   my ( $re ) = @_;

   # Perl tries to put (?-ixsm:RE) around our pattern. Lets attempt to remove
   # it if we can
   return "/$1/"  if $re =~ m/^\(\?-xism:(.*)\)$/;
   return "/$1/i" if $re =~ m/^\(\?i-xsm:(.*)\)$/;

   # Failed. Lets just be safe then
   return "/$re/";
}

sub eval_cond_matches
{
   shift; # class
   my ( $event, $results, $re ) = @_;

   my $text = $event->{text}->str;

   pos( $text ) = 0;

   my $matched;

   while( $text =~ m/$re/g ) {
      my @matchgroups;
      for ( 0 .. $#+ ) {
         my ( $start, $end ) = ( $-[$_], $+[$_] );
         my $len = $end - $start;

         push @matchgroups, [ $start, $len ];
      }

      $results->push_result( "matchgroups", \@matchgroups );
      $matched = 1;
   }

   return $matched;
}

###### ACTIONS

### FORMAT

sub parse_action_format
   : Rule_description("Apply formatting to the line or matched parts")
   : Rule_format('line|matches|match(number) key="value" [key="value" ...]')
{
   shift; # class
   my ( $spec ) = @_;

   $spec =~ s/^(\w+)\s*// or die "Expected type as first argument\n";
   my $type = $1;

   my $groupnum;

   if( $type eq "line" ) {
      $groupnum = -1;
   }
   elsif( $type eq "matches" ) {
      $groupnum = 0;
   }
   elsif( $type eq "match" ) {
      $spec =~ s/^\((\d+)\)\s*// or die "Expected match group number\n";
      $groupnum = $1;
   }
   else {
      die "Unrecognised format type $type\n";
   }

   my %format;
   while( $spec =~ s/^(\w+)=// ) {
      my $name = $1;

      my $value = extract_delimited( $spec, q{"'} );
      s/^["']//, s/["']$// for $value;

      $format{$name} = $value;

      $spec =~ s/^\s+//;
   }

   if( length $spec ) {
      die "Unrecognised format spec $spec\n";
   }

   return ( $groupnum, \%format );
}

sub deparse_action_format
{
   shift; # class
   my ( $groupnum, $formathash ) = @_;

   return unless %$formathash;

   my $type = $groupnum == -1 ? "line" :
              $groupnum ==  0 ? "matches" :
                                "match($groupnum)";

   return "$type ".join( " ", map { qq($_="$formathash->{$_}") } sort keys %$formathash );
}

sub eval_action_format
{
   shift; # class
   my ( $event, $results, $groupnum, $formathash ) = @_;

   my $str = $event->{text};

   if( $groupnum == -1 ) {
      $str->apply_tag( 0, -1, $_, $formathash->{$_} ) for keys %$formathash;
   }
   else {
      foreach my $groups ( @{ $results->get_result( "matchgroups" ) } ) {
         my $group = $groups->[$groupnum] or next;
         my ( $start, $len ) = @$group;

         $str->apply_tag( $start, $len, $_, $formathash->{$_} ) for keys %$formathash;
      }
   }
}

### UNFORMAT

sub parse_action_unformat
   : Rule_description("Remove formatting from the line or matched parts")
   : Rule_format('line|matches|match(number) key [key ...]')
{
   shift; # class
   my ( $spec ) = @_;

   $spec =~ s/^(\w+)\s*// or die "Expected type as first argument\n";
   my $type = $1;

   my $groupnum;

   if( $type eq "line" ) {
      $groupnum = -1;
   }
   elsif( $type eq "matches" ) {
      $groupnum = 0;
   }
   elsif( $type eq "match" ) {
      $spec =~ s/^\((\d+)\)\s*// or die "Expected match group number\n";
      $groupnum = $1;
   }
   else {
      die "Unrecognised format type $type\n";
   }

   my @tags;
   while( $spec =~ s/^(\w+)// ) {
      my $name = $1;

      push @tags, $name;

      $spec =~ s/^\s+//;
   }

   if( length $spec ) {
      die "Unrecognised format spec $spec\n";
   }

   return ( $groupnum, \@tags );
}

sub deparse_action_unformat
{
   shift; # class
   my ( $groupnum, $taglist ) = @_;

   my $type = $groupnum == -1 ? "line" :
              $groupnum ==  0 ? "matches" :
                                "match($groupnum)";

   my $ret = $type;
   $ret .= " $_" for @$taglist;

   return $ret;
}

my @alltags = qw( fg bg b u i );

sub eval_action_unformat
{
   shift; # class
   my ( $event, $results, $groupnum, $taglist ) = @_;

   $taglist = \@alltags unless @$taglist;

   my $str = $event->{text};

   if( $groupnum == -1 ) {
      $str->unapply_tag( 0, -1, $_ ) for @$taglist;
   }
   else {
      foreach my $groups ( @{ $results->get_result( "matchgroups" ) } ) {
         my $group = $groups->[$groupnum] or next;
         my ( $start, $len ) = @$group;

         $str->unapply_tag( $start, $len, $_ ) for @$taglist;
      }
   }
}

### LEVEL

sub parse_action_level
   : Rule_description("Set the activity level for the targetted item")
   : Rule_format('$level')
{
   shift; # class
   my ( $spec ) = @_;

   $spec =~ s/^(\d)// or die "Expected level number as first argument\n";
   my $level = $1;

   $level >= 0 and $level <= 3 or die "Expected 'level' between 0 and 3\n";

   return ( $level );
}

sub deparse_action_level
{
   shift; # class
   my ( $level ) = @_;

   return "$level";
}

sub eval_action_level
{
   shift; # class
   my ( $event, $results, $level ) = @_;

   $event->{level} = $level;
}

1;
