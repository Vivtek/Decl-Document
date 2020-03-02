#!perl -T
use 5.006;
use strict;
use warnings;
use Test::More;
use Data::Dumper;
$Data::Dumper::Useqq = 1;

use Decl::Document;

my $input;
my $d;


# -------------------------------------
# First, just some dead-simple basic tag structure.
$input = <<'EOF';
tag name (thing) # comment
  text "example"
EOF

$d = Decl::Document->from_string ($input);
ok ($d->has_content);
my $c = $d->content;
ok ($c->is('tag'));
is ($c->name, 'name');
ok ($c->parm('thing'));
ok (not $c->parm('other'));

my $child = $c->child_n(0);
ok ($child->is('text'));
ok ($child->has_string);
is ($child->string, 'example');

is ($d->to_string(), <<'EOF');
tag name (thing) # comment
    text "example"
EOF

$d->no_content;
is ($d->to_string(), '');
#diag "\n" . $d->to_string();

# -------------------------------------
# Now how about a document with more than one top-level tag?
$input = <<'EOF';
tag one (thing)
  text "example"
  
tag two
tag three
tag four
EOF

$d = Decl::Document->from_string ($input);
is ($d->has_content, 4);
my @c = $d->content;
is ($c[2]->name, 'three');
is ($d->to_string(), <<'EOF');
tag one (thing)
    text "example"

tag two

tag three

tag four
EOF

# -------------------------------------
# Now, let's "parse" some flat text.
$input = <<'EOF';
This is text.
Two lines.
Three lines woo.
EOF

$d = Decl::Document->from_string ($input, type=>'text');
is ($d->to_string(), <<'EOF');
This is text.
Two lines.
Three lines woo.
EOF

is ($d->to_string(2), <<'EOF');
  This is text.
  Two lines.
  Three lines woo.
EOF

# -------------------------------------
# Parsing an embedded text.
$input = <<'EOF';
text "string":
  This is a two-lined text
  piece just for testing.
  
tag after
EOF

$d = Decl::Document->from_string ($input);
is ($d->has_content, 2);
(@c) = $d->content;
$c = $c[0];
is ($c->tag, 'text');
is ($c->sigil, ':');
is ($c->has_children, 1);

my $c2 = $c->child_n(0);
is ($c2->{document}->{parent}, $d);
is ($c2->{document}->{owning_node}, $c);
ok ($c2->has_dtext);
is ($c2->linenum, 2);
is ($c2->dtext, <<'EOF');
This is a two-lined text
piece just for testing.
EOF
is ($c2->canon_syntax, <<'EOF');
: This is a two-lined text
  piece just for testing.
EOF
is ($c->canon_syntax, <<'EOF');
text "string":
    This is a two-lined text
    piece just for testing.
EOF


$c = $c[1];
is ($c->tag, 'tag');
is ($c->name, 'after');
is ($c->linenum, 5);

is ($d->to_string(), <<'EOF');
text "string":
    This is a two-lined text
    piece just for testing.

tag after
EOF

$input = <<'EOF';
text "string":
  This is a two-lined text
  piece just for testing.
  
EOF
$d = Decl::Document->from_string ($input);

is ($d->to_string(), <<'EOF');
text "string":
    This is a two-lined text
    piece just for testing.
EOF

# Now some indented text starting on the line.

$input = <<'EOF';
text: Here is a two-lined indented
      text starting on the line after a sigil.
  
tag after
EOF

$d = Decl::Document->from_string ($input);
is ($d->has_content, 2);
(@c) = $d->content;
$c = $c[0];
is ($c->tag, 'text');
is ($c->sigil, ':');
ok (not $c->has_children);
ok ($c->has_dtext);
is ($c->canon_syntax, <<'EOF');
text: Here is a two-lined indented
      text starting on the line after a sigil.
EOF
is ($c[1]->tag,  'tag');
is ($c[1]->name, 'after');

# Now a sigiled text child.
$input = <<'EOF';
master tag
  - Here is a bullet point
  - And another; they are separate sigiled text children
    and they can be multilined.
EOF

$d = Decl::Document->from_string ($input);
is ($d->has_content, 1);
(@c) = $d->content;
$c = $c[0];
is ($c->tag, 'master');
is ($c->has_children, 2);
is ($c->child_n(0)->canon_syntax, "- Here is a bullet point\n");
is ($c->child_n(1)->canon_syntax, <<'EOF');
- And another; they are separate sigiled text children
  and they can be multilined.
EOF


done_testing();
