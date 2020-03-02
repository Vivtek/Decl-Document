package Decl::Syntax::Cursor;

use 5.006;
use strict;
use warnings;

=head1 NAME

Decl::Syntax::Cursor - Wraps a line iterator with some useful Decl parsing-specific behavior

=head1 VERSION

Version 0.03

=cut

our $VERSION = '0.03';

=head1 SUBROUTINES/METHODS

=head2 new

Creates a new parsing cursor in a given document ("context").

=cut

sub new {
   my ($class, $iter) = @_;
   my $self = bless ({}, $class);

   $self->{iter} = $iter;
   $self->{next_line} = $iter->();
   $self->{done} = defined $self->{next_line} ? 0 : 1;
   $self->{line} = defined $self->{next_line} ? $self->{next_line}->[0] : 1;
   $self->{last_linenum} = $self->{line};
   
   return $self;
}

=head2 next, next_nonblank

Gets the next line; each line is [linenum, indent, text], unless it's a blank line, which is [linenum, undef, undef]. The "nonblank" variant skips any blank lines
and just goes straight to the next nonblank line.

Records the last line number returned.

When the end of the iterator is reached, sets its "done" flag and from then on returns undef, like any iterator.

=cut

sub next {
   my $self = shift;
   my $peeking = shift || 0;
   my $next_line;

   if ($peeking != 2 and defined $self->{current_blank}) {
      $next_line = [$self->{current_blank}, undef, undef];
      #_log_line_to_stderr ($next_line, 'read cached blank');

      $self->{current_blank} += 1;
      if ($self->{current_blank} > $self->{last_blank}) {
         delete $self->{current_blank};
         delete $self->{last_blank};
      }
      return wantarray ? @$next_line : $next_line;
   }
   
   if ($self->{next_line}) {
      $next_line = $self->{next_line};
      $self->{last_linenum} = $next_line->[0] unless $peeking;
      #_log_line_to_stderr ($next_line, 'read') unless $peeking;
      delete $self->{next_line};
      return wantarray ? @$next_line : $next_line;
   }
   $next_line = $self->{iter}->();
   #_log_line_to_stderr ($next_line, 'read') unless $peeking;
   if (defined $next_line) {
      $self->{last_linenum} = $next_line->[0] unless $peeking;
   } else {
      $self->{done} = 1 unless $peeking;
      return undef;
   }

   return wantarray ? @$next_line : $next_line;
}
sub next_nonblank {
}

=head2 peek, peek_nonblank

Runs the iterator for another line or until a non-blank line is found. Same rules as next/next_nonblank. Does not set "done" or last linenum.

=cut

sub peek {
   my $self = shift;
   my $next_line;
   
   if (defined $self->{current_blank}) {
      $next_line = [$self->{current_blank}, undef, undef];
      #_log_line_to_stderr ($next_line, 'peek cached blank');
      return wantarray ? @$next_line : $next_line;
   }

   $next_line = $self->next(1);
   #_log_line_to_stderr ($next_line, 'peek');
   return unless defined $next_line;
   $self->{next_line} = $next_line;
   wantarray ? @$next_line : $next_line;
}
sub peek_nonblank {
   my $self = shift;
   my $next_line = $self->next(1);
   return unless defined $next_line;
   if (not defined $next_line->[1]) {
      #_log_line_to_stderr ($next_line, 'blank');
      $self->{current_blank} = $next_line->[0];
      $self->{last_blank} = $next_line->[0];
      while ($next_line = $self->next(2)) {
         last if defined $next_line->[1];
         $self->{last_blank} = $next_line->[0];
      }
   }
   $self->{next_line} = $next_line;
   #_log_line_to_stderr ($next_line, 'nonblank at');
   wantarray ? @$next_line : $next_line;
}

=head2 done, last_linenum

Checks the "done" flag or the last linenum encountered.

=cut

sub done         { $_[0]->{done} }
sub last_linenum { $_[0]->{last_linenum} }

sub _log_line_to_stderr {
   my $next_line = shift;
   my $word = shift || 'read';
   if (not defined $next_line) {
      print STDERR "tried to $word line but failed; \$next_line undef\n";
      return;
   }
   my ($linenum, $indent, $text) = @$next_line;
   print STDERR "$word line # $linenum: <blank>\n" unless defined $indent;
   print STDERR "$word line # $linenum indented at $indent: $$text\n" if defined $indent;
}

=head2 extend_subdocument (subdoc, indentation)

This peeks successively from the cursor until either the cursor ends or the next line does not comply with the indentation rule.
The subdocument is extended to the last non-blank line that does comply with the indentation rule (intervening blank lines are not syntactically significant).

=cut

sub extend_subdocument {
   my ($self, $subdoc, $indent) = @_;
   $indent = $subdoc->{indent} unless defined $indent;
   
   #print STDERR "--- extending subdoc from line " . $subdoc->{line} . "\n";
   while (my $next_line = $self->peek_nonblank) {
      my ($linenum, $lineindent, $text) = @$next_line;
      if (defined $lineindent and $lineindent < $indent) {
         #print STDERR "--- finished extending subdoc at " . $subdoc->{last_line} . "\n";
         return $subdoc;
      }
      
      my $actual_next = $self->peek;
      $subdoc->{last_line} = $actual_next->[0] if defined $actual_next->[1];
      #_log_line_to_stderr ($actual_next, 'extended to');
      $self->next;
   }
   #print STDERR "--- finished extending subdoc at " . $subdoc->{last_line} . "\n";
   return $subdoc;
}

=head1 AUTHOR

Michael Roberts, C<< <michael at cpan.org> >>

=head1 BUGS

Please report any bugs or feature requests to C<bug-decl-document at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Decl-Document>.  I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.




=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc Decl::Syntax::Cursor


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

1; # End of Decl::Syntax::Cursor
