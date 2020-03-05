#!perl -T
use 5.006;
use strict;
use warnings;
use Test::More;
use Data::Dumper;
$Data::Dumper::Useqq = 1;

use Decl::Node;

my $n;


$n = Decl::Node->new_from_string(<<'EOF');
n
 t1: some simple dtext with
     a couple of lines
        
 t2:+ blocktext, which will
      parse down
     
      to multiple paragraphs
     
      +tag: blah blah
     
 t3:
   And some off-line text
   of a couple of lines 
   
   with a blank?     
EOF


# Let's get the text from each of these three nodes.
is ($n->child_n(0)->text, <<'EOF');
some simple dtext with
a couple of lines
EOF

is ($n->child_n(1)->text, <<'EOF');
blocktext, which will
parse down

to multiple paragraphs

+tag: blah blah
EOF
is ($n->child_n(2)->text, <<'EOF');
And some off-line text
of a couple of lines

with a blank?
EOF


# Now let's add an out-of-band value. This part of the API is pretty simple.
ok (not $n->has_oob);
$n->set_oob("this is a value");
ok ($n->has_oob);
is ($n->oob(), 'this is a value');
$n->set_oob('x', 5);
is ($n->oob(), 'this is a value');
is ($n->oob('x'), 5);
$n->no_oob;
ok (not $n->has_oob);


done_testing();
