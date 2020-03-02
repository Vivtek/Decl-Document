#!perl -T
use 5.006;
use strict;
use warnings;
use Test::More;
use Data::Dumper;
$Data::Dumper::Useqq = 1;

use Decl::Document;

my $d;

$d = Decl::Document->from_file('t/test1.decl');
ok ($d->has_content);
my (@c) = $d->content;
ok ($c[0]->is('tag'));
ok ($c[1]->is('thing'));

is ($d->{origin_file}, 't/test1.decl');

is ($c[0]->canon_syntax, <<'EOF');
tag file test:
    This should pretty much work the same as any other parse.
EOF
done_testing();
