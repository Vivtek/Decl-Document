#!perl -T
use 5.006;
use strict;
use warnings;
use Test::More;
use Data::Dumper;
$Data::Dumper::Useqq = 1;

use Decl::Document;

my $input;
my ($d, $c, @c);


# -------------------------------------
# Blocktext is plain text, but breaks its content into separate paragraph subdocuments and indented-punctuation subnodes.
# Let's do it at the document level first,
$input = <<'EOF';
This is text.
Two lines.
Three lines woo.

- Quoted bullet point
- Another
EOF

$d = Decl::Document->from_string ($input, type=>'blocktext');
ok ($d->has_content);
is ($d->type, 'blocktext');
is ($d->has_content, 4); # Paragraph, separator, blockquote, blockquote
@c = $d->content;
ok ($c[0]->is_tagless);
ok ($c[1]->is_separator);
ok ($c[2]->is_sigiled);
ok ($c[3]->is_sigiled);
is ($d->to_string(), <<'EOF');
This is text.
Two lines.
Three lines woo.

- Quoted bullet point
- Another
EOF

# -------------------------------------------------
# And let's do one that's embedded into a parent node.

$input = <<'EOF';
block:.
  This is a brief two-lined paragraph
  with some stuff here.
  
  " It is quoted
    with an indented
    blockquote.
    
  And here's another paragraph.
EOF

$d = Decl::Document->from_string ($input);
ok ($d->has_content);
$c = $d->content;
ok ($c->is('block'));
@c = $c->children;
ok ($c[0]->is_tagless);
ok ($c[1]->is_separator);
ok ($c[2]->is_sigiled);
#diag $c[2]->canon_line;
ok ($c[3]->is_separator);
ok ($c[4]->is_tagless);
#diag $c->debug_structure;
#diag $c->canon_syntax;

# -------------------------------------------------
# Finally, one that starts on the parent's line.

$input = <<'EOF';
block:. This is a brief two-lined paragraph
        with some stuff here.
  
        " It is quoted
          with an indented
          blockquote.
    
        And here's another paragraph.
EOF

$d = Decl::Document->from_string ($input);
$c = $d->{content};
#diag $c->debug_structure;
is ($c->canon_syntax, <<'EOF');
block:. This is a brief two-lined paragraph
        with some stuff here.

        " It is quoted
          with an indented
          blockquote.

        And here's another paragraph.
EOF
$c = $c->child_n(0);
#diag $c->child_n(2)->debug_hash;
is ($c->child_n(2)->canon_syntax (10), <<'EOF');
          " It is quoted
            with an indented
            blockquote.
EOF
#diag $d->list_subdocuments->canon_syntax;

# -------------------------------------------------
# Blocktext can nest into an indented para, too.

$input = <<'EOF';
block:.
  This is a brief two-lined paragraph
  with some stuff here.
  
  " It is quoted
    with an indented
    blockquote.
    
    - This blockquote itself contains a bullet list.
    - With two bullets.
    
  And here's another paragraph.
EOF

$d = Decl::Document->from_string ($input);
$c = $d->{content};
is ($c->canon_syntax, <<'EOF');
block:.
    This is a brief two-lined paragraph
    with some stuff here.

    " It is quoted
      with an indented
      blockquote.

      - This blockquote itself contains a bullet list.
      - With two bullets.

    And here's another paragraph.
EOF
is ($d->to_string, <<'EOF');
block:.
    This is a brief two-lined paragraph
    with some stuff here.

    " It is quoted
      with an indented
      blockquote.

      - This blockquote itself contains a bullet list.
      - With two bullets.

    And here's another paragraph.
EOF

$c = $c->child_n(2);
is ($c->canon_syntax, <<'EOF');
" It is quoted
  with an indented
  blockquote.

  - This blockquote itself contains a bullet list.
  - With two bullets.
EOF

$c = $c->child_n(0)->child_n(2); # The API should probably include some kind of "visible child #2" thing so the invisible children don't perennially confuse us.
ok ($c->is_sigiled);
is ($c->tag, '-');
is ($c->canon_syntax, "- This blockquote itself contains a bullet list.\n");

# 2020-03-01 - blocktext seems to be working to my complete satisfaction.

done_testing();
