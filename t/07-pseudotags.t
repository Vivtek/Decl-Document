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
# Annotations/pseudotags are formed with tags in square brackets. (Or actually any brackets.)
$input = <<'EOF';
text "plain ol tag"
  [1]: this is an annotation
  [2]: so is this
  [annotations can have spaces]: this also works
EOF

$d = Decl::Document->from_string ($input);
ok ($d->has_content);
my $c = $d->content;
ok ($c->is('text'));
ok ($c->child_n(1)->pseudo);
is ($c->child_n(1)->tag, '2');
is ($c->canon_syntax, <<'EOF');
text "plain ol tag"
    [1]: this is an annotation
    [2]: so is this
    [annotations can have spaces]: this also works
EOF


$input = <<'EOF';
text "plain ol tag"
  [1]: this is an annotation
  (2): yup
  <insertion point>
  {why even} "a string"
EOF

$d = Decl::Document->from_string ($input);
ok ($d->has_content);
$c = $d->content;
ok ($c->is('text'));
ok ($c->child_n(1)->pseudo);
is ($c->child_n(1)->tag, '2');
is ($c->child_n(0)->pseudo, '[');
is ($c->child_n(1)->pseudo, '(');
is ($c->child_n(2)->pseudo, '<');
is ($c->child_n(3)->pseudo, '{');
is ($c->canon_syntax, <<'EOF');
text "plain ol tag"
    [1]: this is an annotation
    (2): yup
    <insertion point>
    {why even} "a string"
EOF



done_testing();
