#!perl -T
use 5.006;
use strict;
use warnings;
use Test::More;
use Data::Dumper;
$Data::Dumper::Useqq = 1;

use Decl::Syntax::Tagged;
use Decl::Node;

# Now let's build some nodes starting from single lines.
sub testtok {
	my @tok = Decl::Syntax::Tagged::parse_line(shift);
	\@tok;
}
my $tok;
sub testnode {
	my @tok = Decl::Syntax::Tagged::parse_line(shift);
	my $node = Decl::Syntax::Tagged::node_from_line_parse (undef, '', @tok);
	$node;
}
sub ignore {}
my $node;

$node = testnode ("tag name 'string' # comment");
isa_ok ($node, "Decl::Node");
is ($node->tag, 'tag');
ok ($node->is('tag'));

is ($node->has_name, 1);
is ($node->name, 'name');

is ($node->has_string, 1);
is ($node->string, 'string');
is ($node->qstring, '"string"');

ok ($node->has_comment);
is ($node->comment, 'comment');
is ($node->comment_type, '#');

is ($node->canon_line, 'tag name "string" # comment'); # Note that the canonical string quote is a double quote.

# The most basic form of a sigil is just a colon. Anything after a sigil is text. If there's a comment in there, it ends up as part of the text.
# A sigil, however, is defined as *any* extent of non-comment punctuation, whether it starts with a colon or not. It may not mean anything, but that's not our problem here.
$node = testnode ("text:   this is some text    # it looks commented, but it's not");
is ($node->tag, 'text');
is ($node->has_name, 0);
is ($node->has_string, 0);
ok ($node->has_sigil);
is ($node->sigil, ':');

is ($node->canon_line, "text: this is some text    # it looks commented, but it's not");

# Any punctuation counts as a sigil, and a comment after it is considered a comment. A continuation is *not* a comment here; it will be counted as text, if included.
$node = testnode ("text ~~ # This is a comment");
ok ($node->has_sigil);
is ($node->sigil, '~~');
ok ($node->has_comment);
is ($node->comment, 'This is a comment');
is ($node->canon_line, "text ~~ # This is a comment");

# But for instance, a dash is a sigil that introduces text.
$node = testnode ("text - This is text with a dash sigil");
ok ($node->has_sigil);
ok (not $node->is_sigiled);
is ($node->sigil, '-');
ok (not $node->has_comment);
ok ($node->has_dtext);
is ($node->dtext, 'This is text with a dash sigil');
is ($node->canon_line, "text - This is text with a dash sigil");

# A sigil can introduce a line.
$node = testnode ("- A sigiled text line");
ok ($node->is('-'));
ok ($node->is_sigiled);
ok ($node->has_sigil);
is ($node->sigil, '-');
is ($node->dtext, 'A sigiled text line');

is ($node->canon_line, "- A sigiled text line");

# An unclosed bracket is a sigil.
$node = testnode ("code { # comment");
ok ($node->is('code'));
ok (not $node->is_sigiled);
ok ($node->has_sigil);
is ($node->sigil, '{');
ok ($node->has_comment);
is ($node->comment, "comment");

is ($node->canon_line, "code { # comment");

# This is still true of a paren, and text within that paren counts as text.
$node = testnode ("code ( some text");
ok ($node->is('code'));
ok (not $node->is_sigiled);
ok ($node->has_sigil);
is ($node->sigil, '(');
ok (not $node->has_comment);
ok ($node->has_dtext);
is ($node->dtext, 'some text');

is ($node->canon_line, "code ( some text");

# A closed bracket, though, is a code segment. This one's kind of complex, because a bracket within quotes can't affect the matching. Things after the code segment are more line.
$node = testnode ("code { x = 0; '{' { stuff }   } # comment");
ok (not $node->has_sigil);
ok ($node->has_dcode);
is ($node->dcode_type, '{');
is ($node->dcode, "x = 0; '{' { stuff }");
is ($node->comment, "comment");

is ($node->canon_line, "code { x = 0; '{' { stuff } } # comment");

$node = testnode ("code < sql or whatever >");
ok (not $node->has_sigil);
ok ($node->has_dcode);
is ($node->dcode_type, '<');
is ($node->dcode, "sql or whatever");
ok (not $node->has_comment);

is ($node->canon_line, "code < sql or whatever >");

# A closed paren or square bracket is a set of parameters. Parameters are a space- or comma-delimited list of values. Note that barewords can contain punctuation.
# if a parameter doesn't have a value, it is merely "present".
$node = testnode ("tag (x)");
ok ($node->has_parms);
ok ($node->has_inparms);
is_deeply ([$node->inparms], ['x']);
is_deeply ([$node->exparms], []);
is ($node->has_inparms, 1);
is ($node->has_exparms, 0);
ok (not $node->has_exparms);
ok ($node->parm('x'));
ok (not $node->parm('y'));

is ($node->canon_line, "tag (x)");

# A value can be set to a bareword or a quoted string.
$node = testnode ("tag (x=y)");
is ($node->has_parms, 1);
is ($node->has_exparms, 0);
ok ($node->inparm('x'));
is ($node->inparm('x'), 'y');

is ($node->canon_line, 'tag (x=y)');

# or a quoted string.
$node = testnode ("tag (x='bob(')");
is ($node->has_parms, 1);
is ($node->has_exparms, 0);
ok ($node->inparm('x'));
is ($node->inparm('x'), 'bob(');

is ($node->canon_line, 'tag (x="bob(")');

# There are some error conditions. Non-bareword values have to be quoted, otherwise the value will read as a presence value and the remainder of the parms as an error token.
# TODO: warning handling, and testing warnings
$node = testnode ("tag (x=&*&)");
is ($node->has_parms, 1);
is ($node->has_exparms, 0);
ok ($node->inparm('x'));

is ($node->canon_line, 'tag (x)');

# And an equals sign hanging in air is also an error.
$tok = testtok ("tag (x=)");
is ($node->has_parms, 1);
is ($node->has_exparms, 0);
ok ($node->inparm('x'));

is ($node->canon_line, 'tag (x)');

# Parameters are separated by commas. (Note that token lists for parameters get really long really quick.)
$node = testnode ("tag (x, y, z=2)");
is ($node->has_parms, 3);
is_deeply ([$node->inparms], ['x', 'y', 'z']);
ok ($node->inparm('x'));
is ($node->inparm('z'), 2);

is ($node->canon_line, 'tag (x, y, z=2)');

# The commas are optional, though. There's a tradeoff between terseness and readability here, and the canonical form still has commas.
$node = testnode ("tag (x y z=2)");
is ($node->has_parms, 3);
is_deeply ([$node->inparms], ['x', 'y', 'z']);
ok ($node->inparm('x'));
is ($node->inparm('z'), 2);

is ($node->canon_line, 'tag (x, y, z=2)');

# Parms can also be in square brackets.
$node = testnode ("tag [x=1 z=2]");
is ($node->has_parms, 2);
ok (not $node->has_inparms);
ok ($node->has_exparms);
is_deeply ([$node->exparms], ['x', 'z']);
is ($node->exparm('x'), 1);
is ($node->exparm('z'), 2);
ok (not defined $node->exparm('y'));

is ($node->canon_line, 'tag [x=1, z=2]');


# And with that, I think we've implemented all the features we need in our line parser.
#diag(Dumper($tok));
done_testing();
