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
# First we just do a little basic code parse.
$input = <<'EOF';
code {
  This is some random code.
  Coupla lines.
  
  With a blank.
}
EOF

$d = Decl::Document->from_string ($input);
ok ($d->has_content);
my $c = $d->content;
ok ($c->is('code'));
is ($c->name, undef);
ok ($c->has_sigil);
is ($c->sigil, '{');
ok (not $c->has_dcode);
ok ($c->has_code);
is ($c->code_tag, '');
is ($c->code, <<'EOF');
This is some random code.
Coupla lines.

With a blank.
EOF

is ($c->canon_syntax, <<'EOF');
code {
    This is some random code.
    Coupla lines.

    With a blank.
}
EOF


# -------------------------------------
# If there's text on the line after the sigil, it's the "code tag", not a dtext.
# The code tag is not parsed any further at the syntactic level.
$input = <<'EOF';
code { perl
  This is some random code.
  Coupla lines.
  
  With a blank.
}
EOF

$d = Decl::Document->from_string ($input);
ok ($d->has_content);
$c = $d->content;
ok ($c->is('code'));
is ($c->name, undef);
ok ($c->has_code);
is ($c->code_type, '{');
is ($c->code_tag, 'perl');
is ($c->canon_syntax, <<'EOF');
code { perl
    This is some random code.
    Coupla lines.

    With a blank.
}
EOF


# -----------------------------------------------
# An empty code block is still a code block.

$input = <<'EOF';
code {
}
EOF

$d = Decl::Document->from_string ($input);
ok ($d->has_content);
$c = $d->content;
ok ($c->is('code'));
is ($c->name, undef);
ok ($c->has_code);
is ($c->code_type, '{');
is ($c->code_tag, '');
is ($c->code, "");
is ($c->canon_syntax, <<'EOF');
code {
}
EOF




done_testing();
