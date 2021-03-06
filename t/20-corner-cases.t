#!perl -T
use 5.006;
use strict;
use warnings;
use Test::More;
use Data::Dumper;
$Data::Dumper::Useqq = 1;

use Decl::Document;
use Decl::Node;

my $input;
my $d;
my $n;

# This is a place to put the weirder texts that break the parser.
# Ideally I'd do Perl fuzz testing.

$input = <<'EOF';
-
EOF

$d = Decl::Document->from_string ($input);
ok ($d);

# This one's OK, though.
$input = <<'EOF';
-
tag
EOF

$d = Decl::Document->from_string ($input);
ok ($d);

$input = <<'EOF';
- huh

EOF

$d = Decl::Document->from_string ($input);
ok ($d);

# 2020-03-05 - encountered while testing node text retrieval.
$n = Decl::Node->new_from_string(<<'EOF');
n
 t1: some simple dtext with
     a couple of lines
        
 t2:. blocktext, which will
      parse down
     
      to multiple paragraphs
     
      +tag: blah blah
     
 t3:
   And some off-line text
   of a couple of lines 
   
   with a blank?     
EOF
ok ($n);



done_testing();
