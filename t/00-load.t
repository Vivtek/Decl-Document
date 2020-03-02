#!perl -T
use 5.006;
use strict;
use warnings;
use Test::More;

plan tests => 9;

BEGIN {
    use_ok( 'Decl::Document' ) || print "Bail out!\n";
    use_ok( 'Decl::Node' ) || print "Bail out!\n";
    use_ok( 'Decl::Syntax::Line' ) || print "Bail out!\n";
    use_ok( 'Decl::Syntax::Tagged' ) || print "Bail out!\n";
    use_ok( 'Decl::Syntax::Textplus' ) || print "Bail out!\n";
    use_ok( 'Decl::Syntax::Tabular' ) || print "Bail out!\n";
    use_ok( 'Decl::Syntax::Xexp' ) || print "Bail out!\n";
    use_ok( 'Decl::Syntax::Sexp' ) || print "Bail out!\n";
    use_ok( 'Decl::Syntax::Text' ) || print "Bail out!\n";
}

diag( "Testing Decl::Document $Decl::Document::VERSION, Perl $], $^X" );
