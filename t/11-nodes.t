#!perl -T
use 5.006;
use strict;
use warnings;
use Test::More;
use Data::Dumper;
$Data::Dumper::Useqq = 1;

use Decl::Node;

my $n;
my $n2;


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

# Let's try some basic location
is ($n->loc ('n/t2')->tag, 't2');
is ($n->loc ('n/(2)')->tag, 't3');
is ($n->loc ('n/t2/tag')->text, "blah blah"); # 2020-03-05 - OK, I'm legit proud of this working first try.

# How about we build a node with more locatable structure though
$n2 = Decl::Node->new_from_string (<<'EOF');
n n3
  t one
  t two
  not t
  t something
    t: some text
    t: more text
    t: yet more text
EOF

#diag $n2->debug_structure;
is ($n2->loc('t(one)')->canon_line, 't one');
is ($n2->loc('t(something)')->canon_line, 't something');
is ($n2->loc('(3)')->canon_line, 't something');
is ($n2->loc('t(2)')->canon_line, 't something');
is ($n2->loc('n/t(2)/(1)')->text, 'more text');
is ($n2->loc('t(something)/(0)')->text, 'some text');

done_testing();
