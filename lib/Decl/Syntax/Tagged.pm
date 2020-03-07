package Decl::Syntax::Tagged;

use 5.006;
use strict;
use warnings;
use Data::Dumper;
use Decl::Node;
use Decl::Syntax::Text;
use Carp qw(cluck);

=head1 NAME

Decl::Syntax::Tagged - Parser for vanilla tag structure

=head1 VERSION

Version 0.03

=cut

our $VERSION = '0.03';


=head1 SYNOPSIS

Like all Decl parsers, Decl::Syntax::Tagged runs in the ...

=head1 PARSING TEXT EXTENTS

=head2 parse (context, cursor)

Given the parse context and a cursor (an itrecs with [linenum, indent, text] and possibly the next line), the tag parser will read and parse tagged lines until the indentation of the
next line is less than its own. If it encounters a subdocument, it will push that subdocument onto the tree and call out to that subdocument, then resume when it finishes.

=cut

sub parse {
   my ($self, $context, $cursor, $type, $escape) = @_;
   $type = 'tag' unless $type; # We only handle one tag type, but this is not universal for all ::Syntax modules.
   my $next_line = $cursor->next;
   return unless $next_line;
   my ($linenum, $indent, $text) = @$next_line;
   return unless defined $indent;
   
   my $line = $$text;
   if (defined $escape) {
      $line =~ s/^\Q$escape\E//;
   }
   my $node = node_from_line_parse ($context, $line, parse_line($line));
   #print STDERR " >> " . $node->canon_line . "\n";
   $node->{linenum} = $linenum;
   $node->{document} = $context;
   $node->{indent} = $indent;
   $node->{dtext_indent} += $indent if defined $node->{dtext_indent};
   $node->{subdoc_type} = $type;
   
   if ($node->has_dtext) { # If there is dtext on the line after the sigil, and the line after it is indented to align with it, then create and extend a subdocument to include the indented text.
      my ($linenum, $lineindent, $text) = $cursor->peek;
      if (defined $lineindent && $lineindent >= $node->{dtext_indent}) {
         my $subdoc = $context->subdocument (line=>$node->{linenum}, indent=>$node->{dtext_indent}, for=>2);
         $subdoc->{type} = $context->type_from_sigil ($node->sigil);

         $cursor->next;
         $cursor->extend_subdocument ($subdoc, $node->{dtext_indent});
         $node->dtext ($subdoc);
      }
   }
   
   # Right now, if the node is either non-sigiled or has dtext, then we need to check for children at the current cursor position.
   # But before that, we may need to parse the dtext, in which case we won't *have* the dtext to remember whether we need to check for children.
   my $check_for_children = 1;
   $check_for_children = 0 if $node->has_sigil;
   $check_for_children = 1 if $node->has_dtext;
   
   # If we're sigiled and have dtext, but our sigil gives us a type that's not just "text" (which is special), then we have to parse our dtext
   if ($node->has_sigil and $node->has_dtext and ref $node->{text}) {
      Decl::Syntax::Text::parse_dtext_subdocument ($node);
   }

   if ($check_for_children) {
      while ($next_line = $cursor->peek) {
         if (not defined $next_line->[1]) {  # Skip blank lines
             $cursor->next;
             next;
         }
         if ($next_line->[1] <= $indent) {
            last;
         }
         my $child = parse($self, $context, $cursor); # Parse the next line as a child, recursively.
         $node->add_child ($child);
         last if $cursor->done;               # If the child found the end of the iterator, no need to try again.
      }
      return $node;
   }
   
   # If we *do* have a sigil but our dtext didn't start on the parent node, then our content is text and depends on the sigil. Initially we'll just assume a
   # sigil means text, and done. The first line of the content text determines its indentation. TODO: back out indentation as far as the sigil, if appropriate lines encountered.
   $next_line = $cursor->peek;
   return $node unless $next_line; # This takes care of the case of an empty sigil at the end of the file.
   ($linenum, $indent, $text) = @$next_line;
   foreach my $return_node (Decl::Syntax::Text->parse ($context, $cursor, $context->type_from_sigil ($node->sigil))) {
      $node->add_child ($return_node);
      $return_node->{document}->{owning_node} = $node;
   }
   
   return $node;
}
sub _num_or_undef { defined $_[0] ? $_[0] : "undef" }

=head1 PARSING LINES

=head2 parse_line (string, offset)

Given a string that represents a tagged line, tokenize it into its component pieces, which can be barewords (the first is the line's tag, all others are names), ()-parameters, []-parameters,
strings with single or double quotes, code in {}, <>, or (), comments starting with # and extending to the end of the line, or a sigil, which is a trailing set of punctuation that can mean
various things.

The offset is normally not required.

=cut

sub parse_line {
   my $string = shift;
   my $offset = shift || 0;
   
   my @tok;
   my $tok;
   
   NEXT_TOKEN:
   # Does the string start with whitespace? If so, swallow it and update the offset.
   ($offset, $string) = chomp_white ($offset, $string);
   
   # Is the string empty? If so, return our token list.
   return @tok if $string eq '';

   # Does the string start with a bareword? If so, push the bareword token and start over.
   if ($tok = parse_bareword($offset, $string)) {
      push @tok, $tok->[0];
      $offset += $tok->[1];
      $string = $tok->[2];
      goto NEXT_TOKEN;
   }

   # Does the string start with a quoted string? If so, push a quoted string token and start over.
   if ($tok = parse_quoted($offset, $string)) {
      push @tok, $tok->[0];
      $offset += $tok->[1];
      $string = $tok->[2];
      goto NEXT_TOKEN;
   }
   
   # If the string starts with a comment marker (which TODO we should parameterize) then the rest of the string is a single token.
   my $actual_comment_markers = '#';
   my $comment_markers = $actual_comment_markers . '\\\\'; # Continuation marks act like comments for this purpose.
   if ($string =~ /^([$comment_markers])(.*)/) {
      my ($marker, $comment) = ($1, $2);
      my $overall_length = length($comment)+1;
      my $coff = $offset+1;
      ($coff, $comment) = chomp_white ($coff, $comment);

      push @tok, [$offset, $overall_length, $marker,
                     [$offset, 1, $marker, $marker],
                     [$coff, length($comment), '', $comment]
                 ];
      return @tok;
   }
   
   # Does the string start with a closable bracket? If that bracket is closed, we do special processing, but otherwise it's a sigil.
   my $bracket_openers = '\\(<{\\['; # TODO: implement a quoter here if we do parameterization
   if ($string =~ /^([$bracket_openers])(.*)/) {
      my ($remainder, $newoffset, @newtoks) = parse_brackets ($offset, $1, $2); # Look, I can *avoid* inlining functionality, too.
      if ($newoffset != $offset) { # If the offset advanced, we have a code segment *unless* the brackets denote parameters in which case we have to parse the parameters.
         if ($newtoks[0]->[2] eq '(' || $newtoks[0]->[2] eq '[') {
            @newtoks = parse_parameters ($offset, @newtoks);
         }
         push @tok, @newtoks;
         $string = $remainder;
         $offset = $newoffset;
         goto NEXT_TOKEN;
      } # If we didn't advance the offset, the bracket didn't have a match and we'll treat it as a sigil.
   }
   
   # If the string starts with a sequence of punctuation at this point, it's a sigil and anything after it is considered text, unless it's a comment.
   if ($string =~ /^(\p{XPosixPunct}+)(.*)/) {
      my ($sigil, $rest) = ($1, $2);
      my $overall_length = length($rest)+length($sigil);
      my $roff = $offset+length($sigil);
      ($roff, $rest) = chomp_white ($roff, $rest);
      
      push @tok, [$offset, length($sigil), ':', $sigil];
      return @tok unless $rest ne '';
      
      $offset = $roff;

      # If something remained on the line after the sigil, it's either a comment or it's text that could potentially start a new indented document.
      if ($rest =~ /^([$actual_comment_markers])(.*)/) {
         # The remainder is a comment (line continuation is not allowed after a sigil) and does not create a new document.
         my ($marker, $comment) = ($1, $2);
         my $overall_length = length($comment)+1;
         my $coff = $offset+1;
         ($coff, $comment) = chomp_white ($coff, $comment);
         
         push @tok, [$offset, $overall_length, $marker,
                        [$offset, 1, $marker, $marker],
                        [$coff, length($comment), '', $comment]
                    ];
      } else {
         # The remainder is text, not a comment, and therefore potentially starts a new document at this indentation. Not that this has any bearing on us at this level.
         push @tok, [$roff, length($rest), '', $rest];
      }
      
      return @tok;
   }
   
   # If anything is left, this is an error.
   if ($string ne '') {
      push @tok, [$offset, length($string), '!', $string];
   }
   return @tok;
}

=head2 chomp_white (offset, string)

Returns ($offset, $string) with leading spaces removed and the offset updated to match. Tabs are currently 4 spaces, but should be parameterized.

=cut

sub chomp_white {
   my ($offset, $string) = @_;
   if ($string =~ /^(\s+)(.*?)(\s*)$/) {
      my ($white, $meat) = ($1, $2);
      $white =~ s/\t/' ' x 4/ge;    # TODO: parameterize tab size?
      return ($offset + length($white), $meat);
   }
   return ($offset, $string);
}

=head2 parse_bareword (offset, string), parse_quoted (offset, string)

Returns [token, offset increment, rest of line] if the line starts with the named kind of token, otherwise undef.

=cut

sub parse_bareword {
   my ($offset, $string) = @_;
   if ($string =~ /^(\p{XPosixAlpha}\w*)(.*)/) {
      my ($bareword, $rest) = ($1, $2);
      return ([[$offset, length($bareword), '', $bareword], length($bareword), $rest]);
   }
   return undef;
}
sub parse_valueword {
   my ($offset, $string) = @_;
   if ($string =~ /^(\w+)(.*)/) {
      my ($bareword, $rest) = ($1, $2);
      return ([[$offset, length($bareword), '', $bareword], length($bareword), $rest]);
   }
   return undef;
}
sub parse_comma {
   my ($offset, $string) = @_;
   if ($string =~ /^,(.*)/) {
      return ([[$offset, 1, ',', ','], 1, $1]);
   }
   return undef;
}
sub parse_equal {
   my ($offset, $string) = @_;
   if ($string =~ /^=(.*)/) {
      return ([[$offset, 1, '=', '='], 1, $1]);
   }
   return undef;
}

sub parse_quoted {
   my ($offset, $string) = @_;

   # Do we have a single-quoted string?   
   if ($string =~ /^'((?:\\.|[^'])*)'(.*)/) {
      my ($content, $rest) = ($1, $2);
      return ([[$offset, length($content)+2, "'",
                    [$offset, 1, "'", "'"],
                    [$offset+1, length($content), '', $content],
                    [$offset+length($content)+1, 1, "'", "'"]
                 ], length($content)+2, $rest]);
   }

   # How about a double-quoted string?
   if ($string =~ /^"((?:\\.|[^"])*)"(.*)/) {
      my ($content, $rest) = ($1, $2);
      return ([[$offset, length($content)+2, '"',
                    [$offset, 1, '"', '"'],
                    [$offset+1, length($content), '', $content],
                    [$offset+length($content)+1, 1, '"', '"']
                 ], length($content)+2, $rest]);
   }
   return undef;
}

=head2 parse_brackets (offset, bracket, rest of line)

Brackets are recursive, so they have a special procedure. This returns [remainder of line (if any), the new offset, and all new tokens generated within the brackets].
Basically, the rule is simple: if an open bracket is matched on the same line by brackets outside strings, then that entire bracket set is a single code section; for
round and square brackets, we also parse those specifically for parameter values. If the open bracket is *not* matched, then the bracket is a sigil, and we handle the token
list accordingly.

=cut

sub parse_brackets {
   my ($offset, $bracket, $rest) = @_;
   
   # First, eliminate all quoted strings.
   my $copy = $rest;
   while ($copy =~ /('(?:\\.|[^'])*'|\"(?:\\.|[^\"])*\")/) {
      my $string = $1;
      my $rep = ' ' x length($string);
      $copy =~ s/\Q$string\E/$rep/g;
   }
   # Now, eliminate all bracket pairs.
   my $closer = $bracket;
   $closer =~ tr/\(\[<{/)]>}/;
   while ($copy =~ /(\Q$bracket\E(?:\\.|[^$bracket$closer])*\Q$closer\E)/) {
      my $string = $1;
      my $rep = ' ' x length($string);
      $copy =~ s/\Q$string\E/$rep/g;
   }
   # Is there a closer on this line? Note that if it's in a comment, we don't care - any comment goes into the code section.
   if ($copy =~ /^(.*)\Q$closer\E(.*)/) {
      my $closer_offset = length($1);
      my $enclosed = substr($rest, 0, $closer_offset);
      my $eoff = $offset + 1;
      ($eoff, $enclosed) = chomp_white ($eoff, $enclosed);
      return (substr($rest, $closer_offset + 1), $offset + 1 + $closer_offset + 1,
               [$offset, $closer_offset + 2, $bracket,
                  [$offset, 1, $bracket, $bracket],
                  [$eoff, length($enclosed), '', $enclosed],
                  [$offset + 1 + $closer_offset, 1, $bracket, $closer]]);
   }
   return ('', $offset);
}

=head2 parse_parameters ($offset, @newtoks)

Takes the token structure for a bracketed code segment, parses the code segment as a Decl parameter list, and returns the modified token structure.
The token structure is just a list containing a single arrayref, which is probably kind of stupid. I might want to rethink that.

=cut

sub parse_parameters {
   my $offset = shift;
   my $cseg = shift;
   my $string = $cseg->[4]->[3];
   $offset = $cseg->[4]->[0];
   
   my @parms;
   my $tok;
   my $val;
   while ($string ne '') {
      ($offset, $string) = chomp_white ($offset, $string);
      last if $string eq '';

      if ($tok = parse_bareword($offset, $string)) { # The first thing in a parm item must be a bareword.
         if (defined $val) { # But if there's already a val hanging out there, then we've omitted the comma and have to push the presence value out now.
            $val->[2] = '?';
            push @parms, $val;
         }
         $val = $tok->[0];
         $offset += $tok->[1];
         $string = $tok->[2];
      } else {
         push @parms, [$offset, length($string), '!', $string];
         last;
      }
      ($offset, $string) = chomp_white ($offset, $string);
      if ($string eq '') {
         $val->[2] = '?';
         push @parms, $val;
         last;
      }

      if ($tok = parse_equal($offset, $string)) {
         my $value_offset = $offset + $tok->[1];
         my $value_rest = $tok->[2];
         ($value_offset, $value_rest) = chomp_white ($value_offset, $value_rest);
         my $value = parse_quoted($value_offset, $value_rest) || parse_valueword($value_offset, $value_rest);
         if ($value) {
            push @parms, [$val->[0], $value_offset + $value->[1] - $val->[0], '=',
                            $val,
                            $tok->[0],
                            $value->[0]];
            $offset = $value_offset + $value->[1];
            $string = $value->[2];
            $val = undef;
         } else {
            # This is kind of pathological, but we'll call it a presence value followed by an erroneous equals sign.
            $val->[2] = '?';
            $tok->[0]->[2] = '!';
            push @parms, $val, $tok->[0];
            $offset = $value_offset;
            $string = $value_rest;
            $val = undef;
         }
      }
      
      if ($tok = parse_comma($offset, $string)) {
         if (defined $val) { # If there was a presence value, push it now.
            $val->[2] = '?';
            push @parms, $val;
            $val = undef;
         }
         push @parms, $tok->[0];
         $offset += $tok->[1];
         $string = $tok->[2];
      }
      ($offset, $string) = chomp_white ($offset, $string);
      last if $string eq '';
   }
   
   return ([$cseg->[0], $cseg->[1], $cseg->[2], $cseg->[3], @parms, $cseg->[5]]);
}

=head1 BUILDING NODES

Once we have a line parsed, we typically build a node from it. Here's where we do that, using the Node API.

=head2 node_from_line_parse (context, @line tokens)

The parse context will govern some of how a node is built, in ways I'm still working out.

=cut

sub node_from_line_parse {
   my ($context, $text, @tok) = @_;
   my $node;
   if ($tok[0]->[2] eq '') { # The normal case: a tagged line. Create an appropriate node and discard the token.
      $node = Decl::Node->new ($tok[0]->[3], tag_type => 'x');
      shift @tok;
   } elsif ($tok[0]->[2] eq '{' || $tok[0]->[2] eq '<' || $tok[0]->[2] eq '(' || $tok[0]->[2] eq '[') { # An annotation pseudotag
      # In this case, the entire content of the tag is taken in plain text as the "pseudotag", since a closed code segment can't stand on its own.
      my $pseudotag = substr($text, $tok[0]->[0]+1, $tok[0]->[1]-2);
      $pseudotag =~ s/^\s+//;
      $pseudotag =~ s/\s+$//;

      $node = Decl::Node->new ($pseudotag, pseudo=>$tok[0]->[2], tag_type => 'x');
      shift @tok;
   } else { # An anonymous line of whatever token type is coming up; in this case, we don't consume the token because we'll actually process it below.
      $node = Decl::Node->new ('', tag_type => $tok[0]->[2]);
   }
   
   $node->{document} = $context;
   
   while (my $t = shift @tok) {
      if       ($t->[2] eq '') {
         $node->add_name($t->[3]);
      } elsif ($t->[2] eq "'" || $t->[2] eq '"') {
         $node->add_string($t->[4]->[3]);
      } elsif ($t->[2] eq ':') {
         $node->sigil($t->[3]);
         if (@tok) { # If the next token after the sigil is a bareword, it's on-line text or a code tag, depending on whether the sigil is a code sigil or not.
            if ($tok[0]->[2] eq '') {
               if (defined $context and $context->is_code_sigil($t->[3])) {
                  $node->{code_tag} = $tok[0]->[3];
               } else {
                  $node->dtext ($tok[0]->[3]);
                  $node->{dtext_indent} = $tok[0]->[0];
               }
               shift @tok;
            }
         }
      } elsif ($t->[2] eq '{' || $t->[2] eq '<') {
         $node->add_dcode($t->[4]->[3], $t->[2]);
      } elsif ($t->[2] eq '(') {
         my @parms = @$t;
         foreach my $p (@parms) {
            next unless ref $p;
            my ($i, $l, $type, $parm) = @$p;
            if ($type eq '?') {
               $node->add_inparm ($parm);
            } elsif ($type eq '=') {
               $node->add_inparm ($parm->[3], $p->[5]->[2] eq '' ? $p->[5]->[3] : $p->[5]->[4]->[3]);
            }
         }
      } elsif ($t->[2] eq '[') {
         my @parms = @$t;
         foreach my $p (@parms) {
            next unless ref $p;
            my ($i, $l, $type, $parm) = @$p;
            if ($type eq '?') {
               $node->add_exparm ($parm);
            } elsif ($type eq '=') {
               $node->add_exparm ($parm->[3], $p->[5]->[2] eq '' ? $p->[5]->[3] : $p->[5]->[4]->[3]);
            }
         }
      } elsif ($t->[2] eq '#') {
         $node->comment ($t->[4]->[3]);
         $node->comment_type ($t->[3]->[3]);
      }
   }
   
   return $node;
}

=head1 RECONSTRUCTING CODE (UNPARSING)

=head2 to_string (context, node, indent)

Right now, our only option is just using the canonical syntax. Later, we'll look at formatting issues (including preservation of input format).

=cut

sub to_string {
   my ($self, $context, $node, $indent) = @_;
   
   return $node->canon_syntax($indent);
}

=head1 AUTHOR

Michael Roberts, C<< <michael at cpan.org> >>

=head1 BUGS

Please report any bugs or feature requests to C<bug-decl-document at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Decl-Document>.  I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.




=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc Decl::Syntax::Tagged


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

1; # End of Decl::Syntax::Tagged
