package Decl::Document;

use 5.006;
use strict;
use warnings;
use Decl::Node;
use Decl::Syntax::Cursor;
use Iterator::Records;
use Data::Dumper;
use Module::Load;
use Carp;

=head1 NAME

Decl::Document - Represents a document or text extent in a Decl code system, and therefore the parsing context for a hierarchical structure of nodes

=head1 VERSION

Version 0.03

=cut

our $VERSION = '0.03';


=head1 SYNOPSIS

In the Decl data definition language, each extent of text is a I<document>, and each document has a type, optional metadata, and various settings that affect how it will be parsed.
The AST parsed is thus anchored in a structure representing the document it was parsed from (even if that "document" was just a string in memory).

All parsing of Decl structures consists of defining the document and then loading it:

  use Decl::Document;
  my $d = Decl::Document->from_file ('myfile.dect');
  
Putting all our knowledge of the origin of a syntax tree into a document that is a parsing context gives us homoiconity - the document not only knows how we got here, but also
knows how to express a changed syntax tree, should it come to that (or how to express a tree we have created from scratch).

The Decl language relies extensively on various forms of quoting, so a document will normally have subdocuments delineating various quoted sections within the textual structure.
The nodes that represent the derived syntactic tree fit into a single tree spanning the entire document, but each knows the subdocument it derives from.

=head1 CREATING A DOCUMENT

To build nodal structure by parsing text, you create a document. This can be done in a couple of different ways, and the document will reflect how it was done.
All node creation methods can be given metadata to store about the document (and some will store it automatically, for instance the filename provided for a load).

=head2 new

The I<new> function just creates an empty document. If provided with a string or stringref to parse, it will do that, or if given a reference to a Decl::Node it will encapsulate
that structure in a new document. It does this by iterating over indented strings and taking appropriate parsing action.

=cut

sub new {
   my $class = shift;
   my $self = bless({}, $class);
   my $parms = { @_ };
   
   $self->{parent} = undef; # Default: a document has no parent.
   $self->{indent} = 0;     # Top-level document is not indented. Subdocuments will explicitly have an indentation set.
   $self->{line} = 1;       # Top-level document starts on line 1, of course.
   $self->{subdocuments} = [];

   $self->{typetable} = $parms->{typetable};
   
   $self->{keep_src_iter} = $parms->{keep_src_iter} || 0;

   $self->{type} = $parms->{type} || 'tag';
   
   $self->{origin} = 'none';
   if (defined $parms->{string}) {
      $self->{origin} = 'string';
      $self->load_string($parms->{string});
   }
   if (defined $parms->{file}) {
      $self->{origin} = 'file';
      $self->{origin_file} = $parms->{file};
      $self->load_file($parms->{file});
   }

   $self->parse unless $self->{origin} eq 'none';
   $self;
}

=head2 from_string (string), from_stringf (string, ...)

This is just syntactic sugar for a I<new> call, making it explicit that a string will be parsed. If the string is a %s-type parameterized string, use I<from_stringf>.

=cut

sub from_string {
   my $class = shift;
   my $string = shift;
   return $class->new(string => $string, @_);
}

sub from_stringf {
}

=head2 from_document (document)
=head2 from_file (filename or open file)

If you have text in a file (which is not an unusual situation) or you have an IO:: handle you want to parse, I<from_file> is the function you want.

=cut

sub from_file {
   my $class = shift;
   my $file = shift;
   return $class->new(file => $file, @_);
}

=head1 SUBDOCUMENTS

A subdocument is essentially a cursor on the document's text, but it acts like a document in its own right.

=cut

sub has_subdocuments {
   my $self = shift;
   return 0 unless defined $self->{subdocuments};
   return scalar @{$self->{subdocuments}};
}
sub no_subdocuments { delete $_[0]->{subdocuments} } # Use this with care.
sub subdocuments {
   my $self = shift;
   return wantarray ? () : 0 unless defined $self->{subdocuments};
   return @{$self->{subdocuments}};
}

sub subdocument {
   my $parent = shift;
   my $self = bless({}, ref $parent);
   my $parms = { @_ };

   $self->{parent} = $parent;
   push @{$self->{parent}->{subdocuments}}, $self;
   
   $self->{indent}    = $parms->{indent} || 0;
   $self->{line}      = $parms->{from}   || $parms->{line} || $parent->{line};
   $self->{last_line} = $self->{line} + $parms->{for} - 1 if defined $parms->{for};
   $self->{last_line} = $parms->{to}     || $parms->{last_line} || $parent->{last_line} unless defined $self->{last_line};
   
   $self->{type}      = $parms->{type}   || $parent->{type};

   my $sub = sub {
      my $piter = $parent->iter_source();
      sub {
         TRY_AGAIN:
         my $line = $piter->();
         return unless defined $line;
         my ($linenum, $lineind, $text) = @$line;
           
         goto TRY_AGAIN if $linenum < $self->{line};
         goto TRY_AGAIN if defined $self->{last_line} && $linenum > $self->{last_line}; 
      
         return $line if not defined $lineind;
         return [$linenum, $lineind - $self->{indent}, $text] if $self->{indent} <= $lineind;
         my $short = substr ($$text, $self->{indent} - $lineind);
         return [$linenum, 0, \$short];
      }
   };
   $self->{iter} = Iterator::Records->new($sub, ['line', 'indent', 'text']);

   $self;
}

=head2 subdoc_extend (lines), subdoc_unindent (cols)

=cut

sub subdoc_extend {
   my $self = shift;
   my $lines = shift || 1;
   
   return unless $self->{parent}; # Extending a non-subdocument has no effect.
   $self->{last_line} += $lines;
}
sub subdoc_unindent {
   my $self = shift;
   my $chars = shift || 1;
   
   return unless $self->{parent}; # Extending a non-subdocument has no effect.
   $self->{indent} -= $chars;
}

=head2 subdocument_convert

Frees a subdocument from its parent, making a copy of its content. This is required before discarding the parent's content.

=cut

sub subdocument_convert {
   my $self = shift;
   return unless $self->{parent};

   $self->{source} = [];
   my $iter = $self->iter_source;
   while (my $line = $iter->()) {
      push @{$self->{source}}, $line;
   }
   my $sub = sub {
      my @lines = @{$self->{source}};
      sub { shift @lines };
   };
   $self->{iter} = Iterator::Records->new($sub, ['line', 'indent', 'text']);

   my @new_subdocs;
   foreach my $s (@{$self->{parent}->{subdocuments}}) {
      push @new_subdocs, $s unless $s == $self;
   }
   $self->{parent}->{subdocuments} = \@new_subdocs;
   delete $self->{parent};
   $self->{indent} = 0;
   
   return $self->{last_line};
}

=head2 list_subdocuments

Returns a node with one line per document/subdocument, of the form tag (from=1, to=6, indent=12).

=cut

sub list_subdocuments {
   my $self = shift;
   
   my $node;
   if ($self->{parent}) {
      $node = Decl::Node->new_from_line ("doc (from=%s, to=%s, indent=%s)", $self->{line}, $self->{last_line}, $self->{indent});
   } else {
      $node = Decl::Node->new_from_line ("doc (top)");
   }
   foreach my $subdoc ($self->subdocuments) {
      $node->add_child ($subdoc->list_subdocuments);
   }
   $node;
}

=head1 ACCESS

=head2 has_source, no_source, source, load_string, load_file, iter_source

The source of a document is its original text. It is kept as an arrayref of lines, each of which is an arrayref [linenum, indent, text]. This source can be discarded
if required after parsing, leaving only the parsed data structure (some of which will then retain the text anyway).

An indication of "undef" indicates a blank line. Tabs are resolved with 4 spaces.

The source can be iterated over by iter_source, which is an itrecs returning [linenum, indent, text].

=cut

sub has_source {
   my $self = shift;
   return 0 unless defined $self->{source};
   scalar @{$self->{source}};
}
sub no_source { return if $_[0]->{subdocuments}; delete $_[0]->{source}; delete $_[0]->{iter}; }
sub source {
   my $self = shift;
   return wantarray ? () : 0 unless defined $self->{source};
   @{$self->{source}};
}

sub iter_source {
   my $self = shift;
   return sub { return undef } unless $self->{iter};
   $self->{iter}->iter();
}

sub load_string {
   my $self = shift;
   my $string = shift;

   $self->subdocument_convert;
   my $linenum = $self->{last_line} || 0;
   foreach my $line (split /^/, $string) {
      $line =~ s/\s*\n*$//;
      $linenum += 1;
      if ($line eq '') {
         push @{$self->{source}}, [$linenum, undef, undef];
      } elsif ($line =~ /^(\s+)(.*)/) {
         my ($white, $meat) = ($1, $2);
         if (not length ($meat)) {
            push @{$self->{source}}, [$linenum, undef, undef];
         } else {
            $white =~ s/\t/' ' x 4/ge;
            push @{$self->{source}}, [$linenum, length($white), \$meat];
         }
      } else {
         push @{$self->{source}}, [$linenum, 0, \$line];
      }
   }
   my $sub = sub {
      my @lines = @{$self->{source}};
      sub { shift @lines };
   };
   $self->{iter} = Iterator::Records->new($sub, ['line', 'indent', 'text']);
   $self->{last_line} = $linenum;
   return $linenum;
}

sub load_file {
   my $self = shift;
   my $file = shift;

   my $fh;
   unless (open ($fh, "<", $file)) {
      carp "Can't open file $file: $!";  # TODO: in general, Decl needs an error handling system
      return;
   }
   
   $self->subdocument_convert;
   my $linenum = $self->{last_line} || 0;
   while (my $line = <$fh>) {
      $line =~ s/\s*\r*\n*$//; # TODO: Test Windows line endings
      $linenum += 1;
      if ($line eq '') {
         push @{$self->{source}}, [$linenum, undef, undef];
      } elsif ($line =~ /^(\s+)(.*)/) {
         my ($white, $meat) = ($1, $2);
         if (not length ($meat)) {
            push @{$self->{source}}, [$linenum, undef, undef];
         } else {
            $white =~ s/\t/' ' x 4/ge;
            push @{$self->{source}}, [$linenum, length($white), \$meat];
         }
      } else {
         push @{$self->{source}}, [$linenum, 0, \$line];
      }
   }
   my $sub = sub {
      my @lines = @{$self->{source}};
      sub { shift @lines };
   };
   $self->{iter} = Iterator::Records->new($sub, ['line', 'indent', 'text']);
   $self->{last_line} = $linenum;
   return $linenum;
}

=head2 extract_lines, extract_string, write_file

To get a string out of our source text, use C<extract_lines> to get an iterator that returns strings. The lines can also be directed to a string or file with the appropriate functions.
All of these take the parameters, from, for, to, chop, indent: "from" line x, "for" x lines or "to" line x, "chop" x characters from the front of each line, "indent" x characters
in the output.

All these represent rectangular portions of the document's text that can be defined as subdocuments.

=cut

sub extract_line_iterator {
   my $self = shift;
   my %parms = @_;
   
   my $from = $parms{from} || 0;
   my $for  = $parms{for};
   my $to   = $parms{to};
   $to = $from+$for-1 if defined $for;
   my $chop   = $parms{chop};
   my $indent = $parms{indent};
   $chop = -$indent if defined $indent && $indent < 0;

   my $sub = sub {
      my $iter = $self->iter_source;

      sub {
         TRY_AGAIN:
         my $line = $iter->();
         return unless defined $line;
         my ($linenum, $lineind, $text) = @$line;
           
         goto TRY_AGAIN if $linenum < $from;
         goto TRY_AGAIN if defined $to && $linenum > $to; 
      
         my $lt = defined $lineind ? (' ' x $lineind . $$text) : "";
         $lt = substr($lt, $chop) if defined $chop;
         $lt = ' ' x $indent . $lt if defined $indent && $indent > 0 and $lt ne '';
         
         return $lt;
      }
   };
   Iterator::Records->new($sub, ['text']);
}

sub extract_lines {
   my $self = shift;
   $self->extract_line_iterator(@_)->iter();
}

sub extract_string {
   my $self = shift;
   my $iter = $self->extract_lines (@_);
   my $string = '';
   while (1) {
      my $line = $iter->();
      last unless defined $line;
      $string .= "$line\n";
   }
   return $string;
}

=head2 has_content, content, no_content

=cut

sub has_content {
   my $self = shift;
   return 0 unless defined $self->{content};
   return 1 unless $self->{content}->{invisible};
   return $self->{content}->has_children;
}
sub no_content { delete $_[0]->{content} }
sub content    {
   my $self = shift;
   return wantarray ? () : undef unless defined $self->{content};
   return $self->{content} unless $self->{content}->{invisible};
   return $self->{content}->children;
}

=head2 type

=cut

sub type { $_[0]->{type} }

=head1 PARAMETERIZATION OF PARSING

We have two places where the types of different text extents can be determined: mapping from the sigil to a type description, and from a type name to a handler.
The type description is a Decl node - typically a single line, but it doesn't strictly have to be. Its tag is the type name, which maps to a handler.

=head2 type_from_sigil

Text embedded in a document is identified by its sigil, a string of punctuation that delimits it. From the sigil, we can get a type description; this type
description consists of a series of barewords, the first of which names the type and others of which parameterize it.

=cut

our $default_sigils = {
   ':+' => 'textplus',
   ':-' => 'text',
   ':.' => 'blocktext',
   ':' => 'textdef',
   '('  => 'code ( )',
   '<'  => 'code < >',
   '['  => 'code [ ]',
   '{'  => 'code { }',
};

sub type_from_sigil {
   my ($self, $sigil) = @_;
   $sigil = ':' unless $sigil;
   
   my $zero = 0;
   my $flow = 0;
   my $break = 0;
   if ($sigil =~ /(.*)<<(.*)/) {
      $zero = 1;
      $sigil = "$1$2";
   }
   if ($sigil =~ /(.*)>(.*)/) {
      $flow = 1;
      $sigil = "$1$2";
   }
   if ($sigil =~ /(.*),(.*)/) {
      $break = 1;
      $sigil = "$1$2";
   }
   
   my $sigiltable = $self->{sigiltable} || $default_sigils;
   my $type = $sigiltable->{$sigil} || 'text';
   
   if ($type eq 'textdef') {
      $type = 'text';
      $type = 'textplus' if $self->{type} eq 'textplus';
      $type = 'blocktext' if $self->{type} eq 'blocktext';
   }
   
   my @type = ($type);
   push @type, 'zero' if $zero;
   push @type, 'flow' if $flow;
   push @type, 'break' if $break;
   
   return wantarray ? @type : join(' ', @type);
}
sub is_code_sigil {
   my ($self, $sigil) = @_;
   my @type = split / /, $self->type_from_sigil($sigil);
   return $type[0] eq 'code';
}

=head2 parser_from_type

The type descriptor is then used to determine a handler class.

=cut

our $default_types = {
   'tag' => 'Decl::Syntax::Tagged',
   'code' => 'Decl::Syntax::Text',
   'text' => 'Decl::Syntax::Text',
   'textplus' => 'Decl::Syntax::Text',
   'blocktext' => 'Decl::Syntax::Text',
};

sub parser_from_type {
   my ($self, $type) = @_;
   $type = 'text' unless $type;
   
   $type =~ s/\s+$//;  # Chop off anything after whitespace.
   
   my $typetable = $self->{typetable} || $default_types;
   my $parser = $typetable->{$type};
   if (not defined $parser) {
      # TODO: this needs to be a handled error
      $parser = $self->{typetable}->{'text'};
   }
   return $parser;
}

=head1 PARSING

Once things are set up, we invoke the parser set on our input. This is only exposed in the API to allow step-by-step construction of a document. Parsing is only done in the context
of the current document, with the resulting nodes going into the document's content.

=head2 parse()

=cut

sub start_cursor {
   my $self = shift;
   if (not $self->{iter}) {
      carp "Cannot iterate source (sub)document";
      return;
   }
   $self->{current_parse} = Decl::Syntax::Cursor->new ($self->iter_source());
}
sub parse {
   my $self = shift;
   my $type = shift || $self->{type} || 'tag';
   
   if (not $self->{current_parse}) {
      if ($self->{parent}) {
         $self->{current_parse} = $self->{parent}->{current_parse};
      }
      $self->start_cursor unless $self->{current_parse};
   }

   my $parser = $self->parser_from_type ($type);
   load $parser;

   $self->{content} = Decl::Node->new_container;
   while (not $self->{current_parse}->done) {
      foreach my $newnode ($parser->parse($self, $self->{current_parse}, $type)) {
         #print STDERR "Adding node:\n" . $newnode->canon_syntax . "\n";
         $self->{content}->add_child ($newnode);
      }
   }
   $self->{last_linenum} = $self->{current_parse}->{last_linenum};
   delete $self->{current_parse};
   
   if ($self->{content}->invisible && $self->{content}->has_children == 1) {  # If the invisible container node only has a single child from the parse, let's discard the container and keep its child.
      $self->{content} = $self->{content}->child_n(0);
      $self->{content}->{parent} = undef;
   }
}

=head1 OUTPUT

Unparsing is the simplest form of output.

=cut

sub to_string {
   my $self = shift;
   my $indent = shift || 0;
   
   return '' unless $self->{content}; # We don't have a textual representation if we don't have content.
   
   my $type = $self->{type} || 'tag';
   my $typetable = $self->{typetable} || $default_types;
   my $parser = $typetable->{$type};
   if (not defined $parser) {
      # TODO: this needs to be a handled error
      $parser = $self->{typetable}->{'text'};
   }
   load $parser;
   
   $parser->to_string ($self, $self->{content}, $indent);
}

=head1 AUTHOR

Michael Roberts, C<< <michael at cpan.org> >>

=head1 BUGS

Please report any bugs or feature requests to C<bug-decl-document at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Decl-Document>.  I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.




=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc Decl::Document


You can also look for information at:

=over 4

=item * RT: CPAN's request tracker (report bugs here)

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=Decl-Document>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/Decl-Document>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/Decl-Document>

=item * Search CPAN

L<http://search.cpan.org/dist/Decl-Document/>

=back


=head1 ACKNOWLEDGEMENTS


=head1 LICENSE AND COPYRIGHT

Copyright 2020 Michael Roberts.

This program is free software; you can redistribute it and/or modify it
under the terms of the the Artistic License (2.0). You may obtain a
copy of the full license at:

L<http://www.perlfoundation.org/artistic_license_2_0>

Any use, modification, and distribution of the Standard or Modified
Versions is governed by this Artistic License. By using, modifying or
distributing the Package, you accept this license. Do not use, modify,
or distribute the Package, if you do not accept this license.

If your Modified Version has been derived from a Modified Version made
by someone other than you, you are nevertheless required to ensure that
your Modified Version complies with the requirements of this license.

This license does not grant you the right to use any trademark, service
mark, tradename, or logo of the Copyright Holder.

This license includes the non-exclusive, worldwide, free-of-charge
patent license to make, have made, use, offer to sell, sell, import and
otherwise transfer the Package with respect to any patent claims
licensable by the Copyright Holder that are necessarily infringed by the
Package. If you institute patent litigation (including a cross-claim or
counterclaim) against any party alleging that the Package constitutes
direct or contributory patent infringement, then this Artistic License
to you shall terminate on the date that such litigation is filed.

Disclaimer of Warranty: THE PACKAGE IS PROVIDED BY THE COPYRIGHT HOLDER
AND CONTRIBUTORS "AS IS' AND WITHOUT ANY EXPRESS OR IMPLIED WARRANTIES.
THE IMPLIED WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR
PURPOSE, OR NON-INFRINGEMENT ARE DISCLAIMED TO THE EXTENT PERMITTED BY
YOUR LOCAL LAW. UNLESS REQUIRED BY LAW, NO COPYRIGHT HOLDER OR
CONTRIBUTOR WILL BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, OR
CONSEQUENTIAL DAMAGES ARISING IN ANY WAY OUT OF THE USE OF THE PACKAGE,
EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.


=cut

1; # End of Decl::Document
