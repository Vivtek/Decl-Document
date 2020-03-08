#!perl -T
use 5.006;
use strict;
use warnings;
use Test::More;
use Data::Dumper;
$Data::Dumper::Useqq = 1;

use Decl::Document;

my $d;

$d = Decl::Document->from_string (<<'EOF', type => 'textplus');
This is a typical note file we want to index.

+date: 2020-03-07
+url: http://www.vivtek.com

And some more text here.
EOF

is_deeply ($d->index->load, [
   ['date', 'date', 1, 3, '', '2020-03-07'],
   ['url',  'url',  1, 4, '', 'http://www.vivtek.com'],
]);

done_testing();
