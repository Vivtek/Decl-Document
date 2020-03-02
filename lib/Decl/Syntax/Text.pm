package Decl::Syntax::Text;

use 5.006;
use strict;
use warnings;
use Data::Dumper;
use Decl::Syntax::Tagged;
use Module::Load;


=head1 NAME

Decl::Syntax::Text - Parser for text extents, including textplus (text with a quote mode for tags)

=head1 VERSION

Version 0.01

=cut

our $VERSION = '0.01';


=head1 SYNOPSIS

Quick summary of what the module does.

Perhaps a little code snippet.

    use Decl::Syntax::Text;

    my $foo = Decl::Syntax::Text->new();
    ...

=head1 PARSING TEXT EXTENTS

=head2 parse (context, cursor, type), parse_text (context, cursor), parse_textplus (context, cursor), parse_blocktext (context, cursor)

Given the parse context and a cursor (an itrecs with [linenum, indent, text] and possibly the next line), the text parsers read and parse lines until the indentation of the
next line is less than its own. By "parse" we really mean "identify" and expand the subdocument accordingly.

Text comes in three flavors (so far): 'text', which is just plain text until we encounter an appropriately indented line, 'blocktext', which breaks the text into paragraphs
separated by blank lines and allows "subtexts" (which are not separate documents) as indented paragraphs introduced by an initial punctuation mark followed by a space, and
'textplus', which is blocktext plus an escape character initial '+' to introduce a tag.

Blocktext also supports footnotes, which are separate paragraphs introduced by [text].

=cut

sub parse {
   my ($self, $context, $cursor, $type) = @_;

   $type = 'text' unless $type; # Plain text is our default.
   my @type = split / +/, $type;
   return parse_blocktext (@_) if $type[0] eq 'textplus';
   return parse_blocktext (@_) if $type[0] eq 'blocktext';
   return parse_code (@_) if $type[0] eq 'code';
   return parse_text (@_);
}

sub parse_text {
   my ($self, $context, $cursor, $type) = @_;
   my @type = split /\s+/, $type;

   my $next_line = $cursor->next;
   return unless $next_line;
   my ($linenum, $lineindent, $linetext) = @$next_line;
   
   # The $context here is the parent document. We have to first create a subdocument that will be our text extent identified.
   my $subdoc = $context->subdocument(line=>$linenum, last_line=>$linenum);
   
   my $indent = $cursor->{indent} || $lineindent;
   $subdoc->{indent} = $indent;
   $cursor->extend_subdocument ($subdoc, $indent);
   
   return _make_output_node ($subdoc, $type, $type[0]);
}

sub parse_code {
   my ($self, $context, $cursor, $type) = @_;
   my @type = split /\s+/, $type;
   
   my $next_line = $cursor->next;
   return unless $next_line;
   my ($linenum, $lineindent, $linetext) = @$next_line;
   if ($$linetext =~ /^$type[2]/) { # Special handling for an empty code extent
      return _make_output_node (undef, $type, $type[0], $type[2]);
   }
   
   # The $context here is the parent document. We have to first create a subdocument that will be our text extent identified.
   my $subdoc = $context->subdocument(line=>$linenum, last_line=>$linenum);
   
   my $indent = $cursor->{indent} || $lineindent;
   $subdoc->{indent} = $indent;

   $cursor->extend_subdocument ($subdoc, $indent);
   $next_line = $cursor->peek;
   ($linenum, $lineindent, $linetext) = @$next_line;
   if (defined $next_line && $$linetext =~ /^$type[2]/) {     # If the line we stopped on is the closing bracket,
      $next_line = $cursor->next;  # consume that line without extending the subdoc.
   }
   
   return _make_output_node ($subdoc, $type, $type[0], $type[2]);
}

sub parse_blocktext {
   my ($self, $context, $cursor, $type) = @_;
   my @type = split /\s+/, $type;

   my $subdoc;
   my $next_line;
   my @outputnodes = ();
   my $indent;
   my $tagesc = '';
   if ($type[0] eq 'textplus') {
      $tagesc = $type[1] || '+';
   }

   while ($next_line = $cursor->peek) {
      my ($linenum, $lineindent, $linetext) = @$next_line;
      $indent = $lineindent if defined $lineindent and not defined $indent;
      #print STDERR "peeked line# $linenum\n";
      last if defined $lineindent && $lineindent < $indent;
      
      if (not defined $lineindent) { # Blank line?
         $cursor->next; # Consume the line and get another (TODO: only skips a single line)
         $next_line = $cursor->peek;
         last unless defined $next_line; # The effect of this is to refrain from writing a separator if this blank line is the last thing in the indentation extent.

         if ($subdoc) {
            ##print STDERR "Finished subdoc on blank line\n";
            push @outputnodes, _make_output_node ($subdoc, $type, $type[0]);
            $subdoc = undef;
         }
         push @outputnodes, _make_output_node ("\n", $type, $type[0]);
      } elsif ($$linetext =~ /^(\p{XPosixPunct}+\s+)/) { # Line starts with punctuation plus space?
         my $punct = $1;
         my $new_indent = length($punct);
         $punct =~ s/\s+//;
         
         if ($subdoc) { # If there's a pending paragraph, emit it
            #print STDERR "Finished subdoc on blank line\n";
            push @outputnodes, _make_output_node ($subdoc, $type, $type[0]);
            $subdoc = undef;
         }
         $cursor->next; # Consume our first line

         my $subsubdoc = $context->subdocument (line=>$linenum, last_line=>$linenum, indent=>$indent + $new_indent);
         $cursor->extend_subdocument ($subsubdoc);
         my $blockquote = _make_output_node ($subsubdoc, $type, $type[0]);
         $subsubdoc->{type} = $type;
         parse_dtext_subdocument ($blockquote, $subsubdoc);
         $blockquote->sigil ($punct);
         push @outputnodes, $blockquote;
      } elsif ($tagesc && $$linetext =~ /^\Q$tagesc\E/) { # We are in a textplus mode and the line starts with the escape character?
         my $escnode = Decl::Syntax::Tagged->parse ($context, $cursor, 'tag', $tagesc);
         $escnode->{esc_char} = $tagesc;
         push @outputnodes, $escnode;
      } else {  # Normal line
         #print STDERR "Normal line $$linetext\n";
         if (not $subdoc) {
            #print STDERR "Starting subdocument\n";
            $subdoc = $context->subdocument(line=>$linenum, last_line=>$linenum, indent=>$indent);
         }
         $subdoc->{last_line} = $linenum;
         $cursor->next; # Consume the line
      }
   }
   $cursor->next unless defined $next_line; # If we've probed the end of the file with our last peek, go ahead and let the cursor mark itself done.

   if ($subdoc) {
      #print STDERR "Final subdoc\n";
      push @outputnodes, _make_output_node ($subdoc, $type, $type[0]);
   }
   #print STDERR "And done?\n";
   return @outputnodes;
}


sub _make_output_node {
   my ($subdoc, $type, $type0, $type2) = @_;

   my $node = Decl::Node->new ('', defined $subdoc && ref $subdoc ? (document => $subdoc) : ());
   $node->{subdoc_type} = $type;
   $node->{subdoc_type0} = $type0;
   $node->{close_bracket} = $type2;
   if (defined $subdoc) {
      if (ref $subdoc) {
         $node->dtext ($subdoc);
         $node->{linenum} = $subdoc->{line};
      } else {
         $node->dtext ($subdoc);
         $node->{separator} = 1;
      }
   } else {
      $node->dtext ('');
   }
   return $node;
}

sub parse_dtext_subdocument {
   my ($node, $subdoc) = @_;
   $subdoc = $node->{text} unless $subdoc;
   my $type = $subdoc->{type};
   my @type = split /\s+/, $type;
   return if $type[0] eq 'text';  # No need to parse plain text
   return if $type[0] eq 'code';  # or code
   
   $subdoc->start_cursor;
   my $parser = $subdoc->parser_from_type ($type);
   load $parser;

   $subdoc->{content} = Decl::Node->new_container;
   $subdoc->{content}->{document} = $subdoc;
   while (not $subdoc->{current_parse}->done) {
      foreach my $newnode ($parser->parse($subdoc, $subdoc->{current_parse}, $type)) {
         $subdoc->{content}->add_child ($newnode);
      }
   }
   delete $subdoc->{current_parse};
   
   if ($subdoc->{content}->invisible && $subdoc->{content}->has_children == 1) {  # If the invisible container node only has a single child from the parse, let's discard the container and keep its child.
      $subdoc->{content} = $subdoc->{content}->child_n(0);
      $subdoc->{content}->{parent} = undef;
   }
   
   $subdoc->{content}->{parsed_from_dtext} = 1;
   $subdoc->{content}->{subdoc_type} = $type;
   $subdoc->{content}->{subdoc_type0} = $type[0];
   $node->{has_dtext_children} = 1;
   $node->{text} = undef;
   $node->add_child ($subdoc->{content});
}

=head1 RECONSTRUCTING CODE (UNPARSING)

=head2 to_string (context, node, indent)

Displaying a node as text only shows its direct text, indented to its native indentation. If it has non-text things embedded in it (blockquotes or textplus tags) they
will be displayed in their native format.

=cut

sub to_string {
   my ($self, $context, $node, $indent) = @_;

   if ($node->tag) {
      if ($node->{esc_char}) {
         return $node->{esc_char} . $node->canon_syntax($indent);
      } else {
         return $node->canon_syntax($indent);
      }
   }   
   return _to_string_invisible(@_) unless $node->has_dtext;
   my $dtext = $node->{text};
   return ' ' x $indent . $dtext unless ref $dtext;

   return $dtext->extract_string(indent=>$indent);
}

sub _to_string_invisible {
   my ($self, $context, $node, $indent) = @_;
   
   return '' unless $node->{invisible};
   
   my @pieces = map { $self->to_string ($context, $_, $indent) } $node->children;
   return join ("", @pieces);
}


=head1 AUTHOR

Michael Roberts, C<< <michael at cpan.org> >>

=head1 BUGS

Please report any bugs or feature requests to C<bug-decl-document at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Decl-Document>.  I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.




=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc Decl::Syntax::Text


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

1; # End of Decl::Syntax::Text
