#!perl -T
use 5.006;
use strict;
use warnings;
use Test::More;
use Data::Dumper;
$Data::Dumper::Useqq = 1;

use Decl::Syntax::Tagged;

# Here, we test the line parser for tagged lines in detail. Let's define a simple wrapper around the line parser just to simplify formatting.
sub testtok {
	my @tok = Decl::Syntax::Tagged::parse_line(shift);
	\@tok;
}
my $tok;

# And here we go. The basic form of a token is [offset, length, type, text]. The offset is relative to the subdocument's indentation.
$tok = testtok ("tag name 'string' # comment");
is_deeply ($tok, [
  [0, 3, '', 'tag'],
  [4, 4, '', 'name'],
  [9, 8, "'",
     [9, 1, "'", "'"],
     [10, 6, '', 'string'],
     [16, 1, "'", "'"]],
  [18, 9, '#',
     [18, 1, '#', '#'],
     [20, 7, '', 'comment']]
]);

# A line continuation is exactly like a comment at the line parser level.
$tok = testtok ("continuation \\ with comment");
is_deeply ($tok, [
  [0, 12, '', 'continuation'],
  [13, 14, '\\',
     [13, 1, '\\', '\\'],
     [15, 12, '', 'with comment']]
]);

# The most basic form of a sigil is just a colon. Anything after a sigil is text. If there's a comment in there, it ends up as part of the text.
# A sigil, however, is defined as *any* extent of non-comment punctuation, whether it starts with a colon or not. It may not mean anything, but that's not our problem here.
$tok = testtok ("text:   this is some text    # it looks commented, but it's not");
is_deeply ($tok, [
  [0, 4, '', 'text'],
  [4, 1, ':', ':'],
  [8, 55, '', "this is some text    # it looks commented, but it's not"]
]);

# Any punctuation counts as a sigil, and a comment after it is considered a comment. A continuation is *not* a comment here; it will be counted as text, if included.
$tok = testtok ("text ~~ # This is a comment");
is_deeply ($tok, [
  [0, 4, '', 'text'],
  [5, 2, ':', '~~'],
  [8, 19, '#',
     [8, 1, '#', '#'],
     [10, 17, '', 'This is a comment']]
]);

# But for instance, a dash is a sigil that introduces text.
$tok = testtok ("text - This is text with a dash sigil");
is_deeply ($tok, [
  [0, 4, '', 'text'],
  [5, 1, ':', '-'],
  [7, 30, '', "This is text with a dash sigil"]
]);

# A sigil can introduce a line.
$tok = testtok ("- A sigiled text line");
is_deeply ($tok, [
  [0, 1, ':', '-'],
  [2, 19, '', "A sigiled text line"]
]);

# An unclosed bracket is a sigil.
$tok = testtok ("code { # comment");
is_deeply ($tok, [
  [0, 4, '', 'code'],
  [5, 1, ':', '{'],
  [7, 9, '#',
     [7, 1, '#', '#'],
     [9, 7, '', 'comment']]
]);

# This is still true of a paren, and text within that paren counts as text.
$tok = testtok ("code ( some text");
is_deeply ($tok, [
  [0, 4, '', 'code'],
  [5, 1, ':', '('],
  [7, 9, '', 'some text']
]);

# A closed bracket, though, is a code segment. This one's kind of complex, because a bracket within quotes can't affect the matching. Things after the code segment are more line.
$tok = testtok ("code { x = 0; '{' { stuff }   } # comment");
is_deeply ($tok, [
  [0, 4, '', 'code'],
  [5, 26, '{', 
     [5, 1, '{', '{'],
     [7, 20, '', "x = 0; '{' { stuff }"],
     [30, 1, '{', '}']],
  [32, 9, '#',
     [32, 1, '#', '#'],
     [34, 7, '', 'comment']]
]);

# A closed paren or square bracket is a set of parameters. Parameters are a space- or comma-delimited list of values. Note that barewords can contain punctuation.
# if a parameter doesn't have a value, it is merely "present".
$tok = testtok ("tag (x)");
is_deeply ($tok, [
  [0, 3, '', 'tag'],
  [4, 3, '(', 
     [4, 1, '(', '('],
     [5, 1, '?', 'x'],
     [6, 1, '(', ')']]
]);

# A value can be set to a bareword or a quoted string.
$tok = testtok ("tag (x=y)");
is_deeply ($tok, [
  [0, 3, '', 'tag'],
  [4, 5, '(', 
     [4, 1, '(', '('],
     [5, 3, '=',
        [5, 1, '', 'x'],
        [6, 1, '=', '='],
        [7, 1, '', 'y']],
     [8, 1, '(', ')']]
]);

# or a quoted string.
$tok = testtok ("tag (x='bob(')");
is_deeply ($tok, [
  [0, 3, '', 'tag'],
  [4, 10, '(', 
     [4, 1, '(', '('],
     [5, 8, '=',
        [5, 1, '', 'x'],
        [6, 1, '=', '='],
        [7, 6, "'",
           [7, 1, "'", "'"],
           [8, 4, '', 'bob('],
           [12, 1, "'", "'"]]],
     [13, 1, '(', ')']]
]);

# There are some error conditions. Non-bareword values have to be quoted, otherwise the value will read as a presence value and the remainder of the parms as an error token.
$tok = testtok ("tag (x=&*&)");
is_deeply ($tok, [
  [0, 3, '', 'tag'],
  [4, 7, '(', 
     [4, 1, '(', '('],
     [5, 1, '?', 'x'],
     [6, 1, '!', '='],
     [7, 3, '!', '&*&'],
     [10, 1, '(', ')']]
]);

# And an equals sign hanging in air is also an error.
$tok = testtok ("tag (x=)");
is_deeply ($tok, [
  [0, 3, '', 'tag'],
  [4, 4, '(', 
     [4, 1, '(', '('],
     [5, 1, '?', 'x'],
     [6, 1, '!', '='],
     [7, 1, '(', ')']]
]);

# Parameters are separated by commas. (Note that token lists for parameters get really long really quick.)
$tok = testtok ("tag (x, y, z=2)");
is_deeply ($tok, [
  [0, 3, '', 'tag'],
  [4, 11, '(', 
     [4, 1, '(', '('],
     [5, 1, '?', 'x'],
     [6, 1, ',', ','],
     [8, 1, '?', 'y'],
     [9, 1, ',', ','],
     [11, 3, '=',
        [11, 1, '', 'z'],
        [12, 1, '=', '='],
        [13, 1, '', 2]],
     [14, 1, '(', ')']]
]);

# The commas are optional, though. There's a tradeoff between terseness and readability here.
$tok = testtok ("tag (x y z=2)");
is_deeply ($tok, [
  [0, 3, '', 'tag'],
  [4, 9, '(', 
     [4, 1, '(', '('],
     [5, 1, '?', 'x'],
     [7, 1, '?', 'y'],
     [9, 3, '=',
        [9, 1, '', 'z'],
        [10, 1, '=', '='],
        [11, 1, '', 2]],
     [12, 1, '(', ')']]
]);

# Parms can also be in square brackets.
$tok = testtok ("tag [x=1 z=2]");
is_deeply ($tok, [
  [0, 3, '', 'tag'],
  [4, 9, '[', 
     [4, 1, '[', '['],
     [5, 3, '=',
        [5, 1, '', 'x'],
        [6, 1, '=', '='],
        [7, 1, '', 1]],
     [9, 3, '=',
        [9, 1, '', 'z'],
        [10, 1, '=', '='],
        [11, 1, '', 2]],
     [12, 1, '[', ']']]
]);

# And with that, I think we've implemented all the features we need in our line parser.
#diag(Dumper($tok));
done_testing();
