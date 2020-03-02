#!perl -T
use 5.006;
use strict;
use warnings;
use Test::More;
use Data::Dumper;
$Data::Dumper::Useqq = 1;

use Decl::Document;

my $d;

$d = Decl::Document->new();
ok (not $d->has_source);
$d->load_string (<<'EOF');
line 1
  line 2
    line 3: here is some indentation
            that is aligned; we'll
            try a subdocument
            
line 4:
  This would be a separate subdocument
  and again it's two lines.
EOF
is ($d->has_source, 9);

# A source iterator is the low-level way to get text back out.
my $i = $d->iter_source;
is_deeply ($i->(), [1, 0, \'line 1']);
is_deeply ($i->(), [2, 2, \'line 2']);
is_deeply ($i->(), [3, 4, \'line 3: here is some indentation']);
is_deeply ($i->(), [4, 12, \"that is aligned; we'll"]);
is_deeply ($i->(), [5, 12, \'try a subdocument']);
is_deeply ($i->(), [6, undef, undef]);
is_deeply ($i->(), [7, 0, \'line 4:']);
is_deeply ($i->(), [8, 2, \'This would be a separate subdocument']);
is_deeply ($i->(), [9, 2, \"and again it's two lines."]);
is ($i->(), undef);

# Just check that a new iterator starts from the beginning.
$i = $d->iter_source;
is_deeply ($i->(), [1, 0, \'line 1']);
is_deeply ($i->(), [2, 2, \'line 2']);

# We can also extract a \n-delineated string in various configurations.
is ($d->extract_string, <<'EOF');
line 1
  line 2
    line 3: here is some indentation
            that is aligned; we'll
            try a subdocument

line 4:
  This would be a separate subdocument
  and again it's two lines.
EOF

is ($d->extract_string(from=>3), <<'EOF');
    line 3: here is some indentation
            that is aligned; we'll
            try a subdocument

line 4:
  This would be a separate subdocument
  and again it's two lines.
EOF

is ($d->extract_string(from=>3, for=>3), <<'EOF');
    line 3: here is some indentation
            that is aligned; we'll
            try a subdocument
EOF

is ($d->extract_string(to=>2), <<'EOF');
line 1
  line 2
EOF

is ($d->extract_string(indent=>2), <<'EOF');
  line 1
    line 2
      line 3: here is some indentation
              that is aligned; we'll
              try a subdocument

  line 4:
    This would be a separate subdocument
    and again it's two lines.
EOF

is ($d->extract_string(chop=>12, from=>3, for=>3), <<'EOF');
here is some indentation
that is aligned; we'll
try a subdocument
EOF

# And we can do all that with iterators, too. (It's actually done with iterators to start with.)
my $lines = $d->extract_lines (from=>3, for=>3);
is ($lines->(), "    line 3: here is some indentation");
is ($lines->(), "            that is aligned; we'll");
is ($lines->(), "            try a subdocument");
is ($lines->(), undef);

# Subdocuments.
ok (not $d->has_subdocuments);
my $s = $d->subdocument(from=>3, for=>2, indent=>13);
ok ($d->has_subdocuments);

is ($s->extract_string, <<'EOF');
ere is some indentation
hat is aligned; we'll
EOF

$s->subdoc_extend (1);
is ($s->extract_string, <<'EOF');
ere is some indentation
hat is aligned; we'll
ry a subdocument
EOF

$s->subdoc_unindent(1);
is ($s->extract_string, <<'EOF');
here is some indentation
that is aligned; we'll
try a subdocument
EOF

is ($d->list_subdocuments->canon_syntax, <<'EOF');
doc (top)
    doc (from=3, to=5, indent=12)
EOF

$s->subdocument_convert;
is ($d->list_subdocuments->canon_syntax, <<'EOF');
doc (top)
EOF

is ($s->extract_string, <<'EOF');
here is some indentation
that is aligned; we'll
try a subdocument
EOF

# Now we make a new subdocument ....
$s = $d->subdocument(from=>3, for=>3, indent=>12);
is ($s->extract_string, <<'EOF');
here is some indentation
that is aligned; we'll
try a subdocument
EOF

# add some text to the original document ...
$d->load_string (<<'EOF');
line 5: something new
line 6
EOF

# confirm that didn't break the subdoc ...
is ($s->extract_string, <<'EOF');
here is some indentation
that is aligned; we'll
try a subdocument
EOF

# and confirm the new text was actually loaded.
is ($d->extract_string, <<'EOF');
line 1
  line 2
    line 3: here is some indentation
            that is aligned; we'll
            try a subdocument

line 4:
  This would be a separate subdocument
  and again it's two lines.
line 5: something new
line 6
EOF


done_testing();
