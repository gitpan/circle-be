#  You may distribute under the terms of the GNU General Public License
#
#  (C) Paul Evans, 2008-2010 -- leonerd@leonerd.org.uk

package Circle::Widget::Label;

use strict;
use warnings;

use base qw( Circle::Widget );

use Tangence::Constants;

our %PROPS = (
   text => {
      dim  => DIM_SCALAR,
      type => 'str',
   },
);

1;
