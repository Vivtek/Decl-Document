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
    : some loose text here
    : some more
    :+ yeah, textplus
       is always rockin
       +date: 2020-03-05
EOF

#diag $n2->canon_syntax;
#diag $n2->debug_structure;
is ($n2->loc('t(one)')->canon_line, 't one');
is ($n2->loc('t(something)')->canon_line, 't something');
is ($n2->loc('(3)')->canon_line, 't something');
is ($n2->loc('t(2)')->canon_line, 't something');
is ($n2->loc('n/t(2)/(1)')->text, 'more text');
is ($n2->loc('t(something)/(0)')->text, 'some text');
is ($n2->loc('t(something)/(3)')->text, 'some loose text here');
is ($n2->loc('t(something)/:')->text, 'some loose text here'); # The sigil of a sigiled node counts as a tag for location (and for everything, actually)
is ($n2->loc('t(something)/:(1)')->text, 'some more');
is ($n2->loc('t(something)/:+/date')->text, '2020-03-05'); # Yeah, this kinda rocks


is ($n2->locf('t(%s)', 'one')->canon_line, 't one');
is ($n2->locf('(%d)', 3)->canon_line, 't something');
is ($n2->locf('t(%s)', 2)->canon_line, 't something');
is ($n2->locf('t(%s)/(%d)', 'something', 3)->text, 'some loose text here');

# Now let's walk that whole thing and ask every node for its path
#diag $n->debug_structure;
#diag $n->loc('t3.(0)')->debug_hash;
my $iter = $n->iterate(sub {
   my $self = shift;
   my $level = shift;
   
   return ['tag', 'path'] unless defined $self;
   return [$self->tag, scalar $self->path];
});
is_deeply ($iter->load(), [
  ['n', 'n'],
  ['t1', 'n.t1'],
  ['t2', 'n.t2'],
  ['', undef],
  ['', 'n.t2.(0)'],
  ['', undef],
  ['', 'n.t2.(1)'],
  ['', undef],
  ['tag', 'n.t2.tag'],
  ['t3', 'n.t3'],
  ['', 'n.t3.(0)'],
]);

$iter = $n2->iterate(sub {
   my $self = shift;
   my $level = shift;
   
   return ['tag', 'path'] unless defined $self;
   return [$self->tag, scalar $self->path];
});
is_deeply ($iter->load(), [
  ['n', 'n'],
  ['t', 'n.t'],
  ['t', 'n.t(1)'],
  ['not', 'n.not'],
  ['t', 'n.t(2)'],
  ['t', 'n.t(2).t'],
  ['t', 'n.t(2).t(1)'],
  ['t', 'n.t(2).t(2)'],
  [':', 'n.t(2).:'],
  [':', 'n.t(2).:(1)'],
  [':+', 'n.t(2).:+'],
  ['', undef],
  ['', 'n.t(2).:+.(0)'],
  ['date', 'n.t(2).:+.date'],
]);

$n2->loc('t(2).:')->delete;
is ($n2->canon_syntax, <<'EOF');
n n3
    t one
    t two
    not t
    t something
        t: some text
        t: more text
        t: yet more text
        : some more
        :+ yeah, textplus
           is always rockin
           +date: 2020-03-05
EOF
is_deeply ($iter->load(), [
  ['n', 'n'],
  ['t', 'n.t'],
  ['t', 'n.t(1)'],
  ['not', 'n.not'],
  ['t', 'n.t(2)'],
  ['t', 'n.t(2).t'],
  ['t', 'n.t(2).t(1)'],
  ['t', 'n.t(2).t(2)'],
  [':', 'n.t(2).:'],
  [':+', 'n.t(2).:+'],
  ['', undef],
  ['', 'n.t(2).:+.(0)'],
  ['date', 'n.t(2).:+.date'],
]);

$n2->add_child_at (0, Decl::Node->new_from_line ('new thing'));
$n2->add_child_at (3, Decl::Node->new_from_line ('newer thing'));
is ($n2->canon_syntax, <<'EOF');
n n3
    new thing
    t one
    t two
    newer thing
    not t
    t something
        t: some text
        t: more text
        t: yet more text
        : some more
        :+ yeah, textplus
           is always rockin
           +date: 2020-03-05
EOF

# Make some room.
$n2->loc('t')->delete;
$n2->loc('not')->delete;
$n2->loc('new')->delete;
is ($n2->canon_syntax, <<'EOF');
n n3
    t two
    newer thing
    t something
        t: some text
        t: more text
        t: yet more text
        : some more
        :+ yeah, textplus
           is always rockin
           +date: 2020-03-05
EOF

$n2->add_child_at (0, Decl::Node->new_from_hash ({tag => 'hash', name=>'tag', text=>'some text'}));
is ($n2->canon_syntax, <<'EOF');
n n3
    hash tag: some text
    t two
    newer thing
    t something
        t: some text
        t: more text
        t: yet more text
        : some more
        :+ yeah, textplus
           is always rockin
           +date: 2020-03-05
EOF
is ($n2->loc('hash')->text, 'some text');

$n2->loc('t')->add_child_at(0, Decl::Node->new_as_text ("a text child\nwith two lines"));
$n2->loc('t')->add_child(Decl::Node->new_as_text ("a second text child", ':!'));
is ($n2->canon_syntax, <<'EOF');  # Note that this kind of shenanigans break homoiconicity, so use them with caution.
n n3
    hash tag: some text
    t two:
        a text child
        with two lines
        :! a second text child
    newer thing
    t something
        t: some text
        t: more text
        t: yet more text
        : some more
        :+ yeah, textplus
           is always rockin
           +date: 2020-03-05
EOF

is ($n2->loc('t.(0)')->canon_syntax, <<'EOF');
: a text child
  with two lines
EOF
ok ($n2->loc('t.(0)')->is_text);
ok ($n2->loc('t.(1)')->is_text);

$n2->loc('t.(0)')->delete;
is ($n2->canon_syntax, <<'EOF');
n n3
    hash tag: some text
    t two:!
        a second text child
    newer thing
    t something
        t: some text
        t: more text
        t: yet more text
        : some more
        :+ yeah, textplus
           is always rockin
           +date: 2020-03-05
EOF

$n2->loc('t.(0)')->delete;
is ($n2->canon_syntax, <<'EOF');
n n3
    hash tag: some text
    t two
    newer thing
    t something
        t: some text
        t: more text
        t: yet more text
        : some more
        :+ yeah, textplus
           is always rockin
           +date: 2020-03-05
EOF

$n2->loc('t')->add_child_text("a text child\nwith two lines");
is ($n2->canon_syntax, <<'EOF');
n n3
    hash tag: some text
    t two:
        a text child
        with two lines
    newer thing
    t something
        t: some text
        t: more text
        t: yet more text
        : some more
        :+ yeah, textplus
           is always rockin
           +date: 2020-03-05
EOF

$n2->loc('hash')->add_child ($n2->loc('newer')->copy);
is ($n2->canon_syntax, <<'EOF');
n n3
    hash tag: some text
        newer thing
    t two:
        a text child
        with two lines
    newer thing
    t something
        t: some text
        t: more text
        t: yet more text
        : some more
        :+ yeah, textplus
           is always rockin
           +date: 2020-03-05
EOF

$n2->loc('hash')->replace ($n2->loc('t(something)/t')->copy);
is ($n2->canon_syntax, <<'EOF');
n n3
    t: some text
    t two:
        a text child
        with two lines
    newer thing
    t something
        t: some text
        t: more text
        t: yet more text
        : some more
        :+ yeah, textplus
           is always rockin
           +date: 2020-03-05
EOF

$n2->loc('newer')->add_before ($n2->loc('t(something)/t')->copy);
is ($n2->canon_syntax, <<'EOF');
n n3
    t: some text
    t two:
        a text child
        with two lines
    t: some text
    newer thing
    t something
        t: some text
        t: more text
        t: yet more text
        : some more
        :+ yeah, textplus
           is always rockin
           +date: 2020-03-05
EOF

$n2->loc('t')->add_after ($n2->loc('newer')->copy);
is ($n2->canon_syntax, <<'EOF');
n n3
    t: some text
    newer thing
    t two:
        a text child
        with two lines
    t: some text
    newer thing
    t something
        t: some text
        t: more text
        t: yet more text
        : some more
        :+ yeah, textplus
           is always rockin
           +date: 2020-03-05
EOF


done_testing();
