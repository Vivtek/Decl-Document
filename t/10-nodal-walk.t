#!perl -T
use 5.006;
use strict;
use warnings;
use Test::More;
use Data::Dumper;
$Data::Dumper::Useqq = 1;

use Decl::Node;

my $input;
my $n;

# A convenient set of fields to extract from some nodes.
sub extractor1 {
   my $self = shift;
   my $level = shift;
   
   return ['tag', 'level', 'line'] unless defined $self;
   return [$self->tag, $level, $self->canon_line];
}


# -------------------------------------
# Here's a tag structure to walk.
$input = <<'EOF';
level1
  level2 (value=2): text
  level2 a
    level3 "a string"
  level2 some more
  text: more text here
EOF

$n = Decl::Node->new_from_string ($input);
my $iter = $n->iterate(\&extractor1);
my $results = $iter->load();
is_deeply ($results, [
 ['level1', 0, 'level1'],
 ['level2', 1, 'level2 (value=2): text'],
 ['level2', 1, 'level2 a'],
 ['level3', 2, 'level3 "a string"'],
 ['level2', 1, 'level2 some more'],
 ['text',   1, 'text: more text here'],
]);

# OK, this walk test is pretty abstract. When you really start to get into record iterators and closures, you see the world differently.
sub accumulator {
   my @accum;
   my $doer = shift;
   my $sub = sub { push @accum, $doer->(shift); };
   return \@accum, $sub;
}

my ($list, $accum) = accumulator(sub { $_[0]->tag });
$accum->($n);
$accum->($n->child_n(0));
is_deeply ($list, ['level1', 'level2']); # This is a sanity check because frankly, closure passing style is confusing.

($list, $accum) = accumulator(sub { $_[0]->tag }); # Reset our accumulator.

my $count = $n->walk ($accum);
is ($count, 6);
is_deeply ($list, ['level1', 'level2', 'level2', 'level3', 'level2', 'text']);

sub extractor_linenum {
   my $self = shift;
   my $level = shift;
   
   return ['tag', 'level', 'linenum'] unless defined $self;
   return [$self->tag, $level, $self->{linenum}];
}
#diag Dumper($n->iterate(\&extractor_linenum)->load);


my $n2 = Decl::Node->new_from_string (<<'EOF');
block:+ Here's some text
        in a little block
        
        " A blockquote
          spanning an extra line.
        
        +tag: Did this get a line number?
EOF
diag Dumper($n2->iterate(\&extractor_linenum)->load);

done_testing();
