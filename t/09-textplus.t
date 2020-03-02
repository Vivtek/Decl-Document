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
# Textplus is just blocktext with an added escape character '+' to embed tagged structure into it.
# Let's do it at the document level first,
$input = <<'EOF';
This is text.
Two lines.

- Quoted bullet point
+date: 2020-03-01
- Another bullet point

EOF

$d = Decl::Document->from_string ($input, type=>'textplus');
ok ($d->has_content);
is ($d->type, 'textplus');
is ($d->has_content, 5); # Paragraph, separator, blockquote, tag, blockquote
@c = $d->content;
ok ($c[0]->is_tagless);
ok ($c[1]->is_separator);
ok ($c[2]->is_sigiled);
is ($c[3]->tag, 'date');
is ($c[3]->dtext, '2020-03-01');
ok ($c[4]->is_sigiled);
is ($c[2]->child_n(0)->{subdoc_type}, 'textplus');
is ($d->to_string(), <<'EOF');
This is text.
Two lines.

- Quoted bullet point
+date: 2020-03-01
- Another bullet point
EOF

# -------------------------------------------------
# And let's do one that's embedded into a parent node.

$input = <<'EOF';
block:+
  This is a brief two-lined paragraph
  with some stuff here.
  
  +date: 2020-03-01
  And here's another paragraph.
EOF

$d = Decl::Document->from_string ($input);
ok ($d->has_content);
is ($d->type, 'tag');
is ($d->has_content, 1);
$c = $d->content;
ok ($c->is('block'));
@c = $c->children;
is (@c, 4); # Paragraph, separator, tag, paragraph
ok ($c[0]->is_tagless);
ok ($c[1]->is_separator);
is ($c[2]->tag, 'date');
ok ($c[3]->is_tagless);
is ($d->to_string, <<'EOF');
block:+
    This is a brief two-lined paragraph
    with some stuff here.

    +date: 2020-03-01
    And here's another paragraph.
EOF

# -------------------------------------------------
# Finally, one that starts on the parent's line.

$input = <<'EOF';
block:+ This is a brief two-lined paragraph
        with some stuff here.
  
        " It is quoted
          with an indented
          blockquote.
    
        +date: 2020-03-01
EOF

$d = Decl::Document->from_string ($input);
is ($d->to_string, <<'EOF');
block:+ This is a brief two-lined paragraph
        with some stuff here.

        " It is quoted
          with an indented
          blockquote.

        +date: 2020-03-01
EOF

# 2020-03-01 - and that's textplus.

done_testing();
