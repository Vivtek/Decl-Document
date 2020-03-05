package Decl::Node;

use 5.006;
use strict;
use warnings;
use List::Util;
use Decl::Syntax::Tagged;
use Decl::Document;
use Iterator::Records;
use Carp qw(cluck);

=head1 NAME

Decl::Node - Represents a single data node in a Decl parse tree

=head1 VERSION

Version 0.03

=cut

our $VERSION = '0.03';


=head1 SYNOPSIS

A Decl node can ordinarily be seen as a unit of parsed content, meaning a tag with parameters. How it is represented in textual format depends on the
document in which it is embedded. We'll end up with a lot of examples.

=head1 CREATING A NODE AND ACCESSING ITS COMPONENTS

A node is canonically built by a parser in the context of a document. However, this data-level API is what parsers use to build nodes,
and judging by past applications I'll find plenty of reasons to build nodes on the fly without a parse context.

There should also be a quick way to parse canonical tagged structure without creating a full document, because this happens a lot. That mode should at least
permit the embedding of text, again without more than a vestigial document. We'll see how that goes.

=head2 new (tag, %parms)

Just creates a new node of a particular tag.

=cut

sub new {
   my $class = shift;
   my $tag = shift;

   my $self = { tag => $tag, @_ };
   bless ($self, $class);
   return $self;
}

=head2 new_container ()

This creates an invisible container node to contain a list of other nodes as its children.

=cut

sub new_container {
   my $class = shift;
   my $self = { tag => '', invisible => 1, indent => 0 };
   $self->{children} = [];
   bless ($self, $class);
   return $self;
}

=head2 new_from_line, new_from_string

There are times when we want a scratch node outside the document structure. I don't currently see how we can get away without any document at all, but
it can be lightweight. The key here is that we want the node, not the document, as our convenient output.

We have two flavors. "New from line" literally parses a single node from a line, and stops when it gets to a line break. This is the only way to guarantee
that the parser will never need a document context, and will be absolutely sufficient for scratch nodes. "New from string" builds a minimal document but returns
the node parsed. That node will be the content node from the document, that is, a normal node if the string defines one tag, or an invisible container if it
defines more than one.

=cut

sub new_from_line {
   my $class = shift;
   my $string = shift;
   if (scalar @_) {
      $string = sprintf ($string, @_);
   }
   Decl::Syntax::Tagged::node_from_line_parse (undef, $string, Decl::Syntax::Tagged::parse_line($string));
}
sub new_from_string {
   my $class = shift;
   my $string = shift;
   if (scalar @_) {
      $string = sprintf ($string, @_);
   }
   my $document = Decl::Document->from_string ($string);
   return $document->content;
}

=head2 STATUS: warnings()

Returns a list of any warnings encountered during parsing of the line for this tag.

=head2 DOCUMENT CONTEXT: document (= in_document), type (whether from doc or standalone), parent, level, invisible

=cut

sub linenum   { $_[0]->{linenum}   }
sub invisible { $_[0]->{invisible} }

=head2 TAGS: tag(), is(), is_sigiled(), pseudo()

The normal tagged line has a tag (that's why they call it a tagged line), but the "tag" can also be a sigil. In this case, the tag is '' and is_sigiled() is true.
In this case, the sigil is returned for ->tag() and is also tested for ->is()
The pseudotag opening bracket is returned for a [pseudotag].

=cut
sub is_sigiled { $_[0]->has_sigil && ($_[0]->{tag} eq '' || $_[0]->{tag} eq $_[0]->{sigil})}
sub tag {$_[0]->is_sigiled ? $_[0]->sigil : $_[0]->{tag}}
sub is_tagless { $_[0]->tag ? 0 : 1 }
sub is_separator { $_[0]->{separator} }
sub is  {$_[0]->is_sigiled ? $_[0]->sigil eq $_[1] : $_[0]->{tag} eq $_[1]}
sub pseudo {$_[0]->{pseudo}}

=head2 NAMES: has_name, names, name([new name]), name_n(#), add_name, no_name
=cut
sub has_name {
   my $self = shift;
   return 0 unless defined $self->{names};
   return scalar @{$self->{names}};
}
sub names {
   my $self = shift;
   return wantarray ? () : 0 unless defined $self->{names};
   return @{$self->{names}};
}
sub name {
   my $self = shift;
   if (not @_) {
      return unless defined $self->{names};
      return $self->{names}->[0];
   }
   $self->{names} = [@_];
   $self->{names}->[0];
}
sub no_name  { delete $_[0]->{names}; }
sub add_name {
   my $self = shift;
   return $self->name(@_) if not defined $self->{names};
   $self->{names} = [@{$self->{names}}, @_];
   $self->{names}->[0];
}
sub name_n {
   my $self = shift;
   my $n = shift || 0;
   return unless defined $self->{names};
   $self->{names}->[$n];
}
   
=head2 PARMS, has_parms, has_inparms, has_exparms, parms(), inparm(name), inparm_n(#), exparm(name), exparm_n(#), no_parms, no_inparms, no_exparms
=cut
sub has_parms { $_[0]->has_inparms + $_[0]->has_exparms }
sub has_inparms { scalar ($_[0]->inparms) || 0 }
sub has_exparms { scalar ($_[0]->exparms) || 0 }
sub no_parms { $_[0]->no_inparms; $_[0]->no_exparms; }
sub no_inparms { delete $_[0]->{inparms}; delete $_[0]->{inparmv}; }
sub no_exparms { delete $_[0]->{exparms}; delete $_[0]->{exparmv}; }
sub inparms {
   my $self = shift;
   return wantarray ? () : 0 unless defined $self->{inparms};   # Note on wantarray trick: https://stackoverflow.com/questions/36072378/how-do-i-return-an-empty-array-array-of-length-0-in-perlreturn ()
   return @{$self->{inparms}};
}
sub exparms {
   my $self = shift;
   return wantarray ? () : 0 unless defined $self->{exparms};
   return @{$self->{exparms}};
}
sub parm { inparm(@_); }
sub inparm {
   my $self = shift;
   my $parm = shift;
   my $value = shift;
   return $self->{inparmv}->{$parm} unless defined $value;
   if (not defined $self->{inparmv}->{$parm}) {
      $self->inparm_add ($parm, $value);
   } else {
      $self->{inparmv}->{$parm} = $value;
   }
   $self->{inparmv}->{$parm};
}
sub add_parm { $_[0]->add_inparm(@_); }
sub add_inparm {
   my $self = shift;
   my $parm = shift;
   my $value = shift || [];
   push @{$self->{inparms}}, $parm;
   $self->{inparmv}->{$parm} = $value;
}
sub parm_n { $_[0]->inparm_n(@_); }
sub inparm_n {
   my $self = shift;
   my $n = shift || 0;
   return unless defined $self->{inparms};
   my $v = $self->{inparmv}->{$self->{inparms}->[$n]};
   return 1 if ref $v;
}
sub exparm {
   my $self = shift;
   my $parm = shift;
   my $value = shift;
   return $self->{exparmv}->{$parm} unless defined $value;
   if (not defined $self->{exparmv}->{$parm}) {
      $self->exparm_add ($parm, $value);
   } else {
      $self->{exparmv}->{$parm} = $value;
   }
   $self->{exparmv}->{$parm};
}
sub add_exparm {
   my $self = shift;
   my $parm = shift;
   my $value = shift || [];
   push @{$self->{exparms}}, $parm;
   $self->{exparmv}->{$parm} = $value;
}
sub exparm_n {
   my $self = shift;
   my $n = shift || 0;
   return unless defined $self->{exparms};
   my $v = $self->{exparmv}->{$self->{exparms}->[$n]};
   return 1 if ref $v;
}


=head2 STRINGS: has_string, no_string, string(), string_n(#), add_string, qstring(), qstring_n(#)
=cut
sub has_string { scalar $_[0]->strings }
sub strings {
   my $self = shift;
   return wantarray ? () : 0 unless defined $self->{strings};
   return @{$self->{strings}};
}
sub string {
   my $self = shift;
   if (not @_) {
      return unless defined $self->{strings};
      return $self->{strings}->[0];
   }
   $self->{strings} = [@_];
   $self->{strings}->[0];
}
sub qstring { _quote_string_value (shift->string); }
sub no_string  { delete $_[0]->{strings}; }
sub add_string {
   my $self = shift;
   return $self->string(@_) if not defined $self->{strings};
   $self->{strings} = [@{$self->{strings}}, @_];
   $self->{strings}->[0];
}
sub string_n {
   my $self = shift;
   my $n = shift || 0;
   return unless defined $self->{strings};
   $self->{strings}->[$n];
}
sub qstring_n { _quote_string_value (shift->string_n(shift)); }

=head2 SIGILS: has_sigil, sigil, no_sigil
=cut
sub has_sigil { defined $_[0]->{sigil} && ( $_[0]->{sigil} ne '') }
sub no_sigil  { delete  $_[0]->{sigil} }
sub sigil {
   my ($self, $sigil) = @_;
   $self->{sigil} = $sigil if defined $sigil;
   return unless defined $self->{sigil};
   $self->{sigil};
}
   
=head2 COMMENTS: has_comment, comment_type, comment, no_comment

A node can only have one comment (because comments go to the end of the line); otherwise they work pretty much like other components.

=cut
sub has_comment  { defined $_[0]->{comment} && ( $_[0]->{comment} ne '' ) }
sub no_comment   { delete $_[0]->{comment} }
sub comment      {
   my ($self, $comment) = @_;
   $self->{comment} = $comment if defined $comment;
   return unless defined $self->{comment};
   $self->{comment};
}
sub comment_type {
   my ($self, $comment_type) = @_;
   $self->{comment_type} = $comment_type if defined $comment_type;
   return $self->{comment_type} if defined $self->{comment_type};
   return '#';
}

=head2 ON-LINE TEXT: has_dtext, no_dtext, dtext_type, dtext
=cut
sub has_dtext  { defined $_[0]->{text} }
sub no_dtext   { delete $_[0]->{text} }
sub dtext      {
   my ($self, $text) = @_;
   $self->{text} = $text if defined $text;
   return unless defined $self->{text};
   return $self->{text}->extract_string if ref $self->{text};
   return $self->{text};
}
sub dtext_type {
   my ($self, $text_type) = @_;
   $self->{text_type} = $text_type if defined $text_type;
   return $self->{text_type} if defined $self->{text_type};
   return '';
}


=head2 ON-LINE CODE: has_dcode, no_dcode, dcode, dcode_type, dcode_n, add_dcode
=cut
sub has_dcode {
   my $self = shift;
   return 0 unless defined $self->{code};
   return scalar @{$self->{code}};
}
sub dcode {
   my $self = shift;
   if (not @_) {
      return unless defined $self->{code};
      return $self->{code}->[0]->[1];
   }
   $self->{code} = [];
   foreach my $code (@_) {
      $self->add_dcode ($code);
   }
   $self->{code}->[0]->[1];
}
sub dcode_type {
   my $self = shift;
   return unless defined $self->{code};
   return $self->{code}->[0]->[0];
}
sub no_dcode  { delete $_[0]->{code}; }
sub add_dcode {
   my $self = shift;
   my $code = shift;
   my $type = shift || '{';
   push @{$self->{code}}, [$type, $code];
   $self->{code}->[0]->[1];
}
sub dcode_n {
   my $self = shift;
   my $n = shift || 0;
   return unless defined $self->{code};
   return $self->{code}->[$n]->[1] unless wantarray;
   return @{$self->{code}->[$n]};
}

=head2 ON-LINE OR CHILD TEXT/CODE: has_text, text_type(#), text(#), has_code, code_type, code

=cut

sub has_text {
   my $self = shift;
   return 1 if $self->has_dtext;
   return 1 if $self->has_sigil;
   return 0;
}
sub text_type { $_[0]->sigil }
sub text {
   my $self = shift;
   return $self->dtext if $self->has_dtext;
   return unless $self->has_children;
   if ($self->child_n(0)->{parsed_from_dtext}) {
      return $self->child_n(0)->canon_syntax;
   }
   $self->child_n(0)->dtext;
}

sub has_code {
   my $self = shift;
   return 1 if $self->has_dcode;
   return 1 if $self->code_tag;
   return 0 unless $self->has_sigil;
   return 0 unless $self->has_children;
   my $first = $self->child_n(0);
   return 1 if defined $first->{subdoc_type0} && $first->{subdoc_type0} eq 'code';
   return 0;
}
sub code_type {
   my $self = shift;
   return $self->dcode_type if $self->has_dcode;
   return $self->sigil;
}
sub code {
   my $self = shift;
   return $self->dcode if $self->has_dcode;
   return undef unless $self->has_code;
   $self->child_n(0)->dtext;
}
sub code_tag { defined $_[0]->{code_tag} ? $_[0]->{code_tag} : '' }

=head2 FORMATTING: has_formatting, formatting

=head1 CHILDREN
=head2 CHILDREN: has_children, children

=cut

sub has_children {
   my $self = shift;
   return 0 unless defined $self->{children};
   return scalar @{$self->{children}};
}
sub children {
   my $self = shift;
   return wantarray ? () : 0 unless defined $self->{children};
   return map { $_->[0] } @{$self->{children}};
}
sub no_children  { delete $_[0]->{children}; }
sub child_n {
   my $self = shift;
   my $n = shift || 0;
   return unless defined $self->{children};
   $self->{children}->[$n]->[0];
}


=head2

We can add, replace, and delete child nodes.
  - replace
  - delete: this is just syntactic sugar for replace, with an empty replacement list
Note that unlike 2015, all children are nodes; some are text nodes within a textual subdocument (the document can be vestigial).


=head2 add_child (node)

Adds a node to the child list. Sets the child's parent.

=cut

sub add_child {
   my ($self, $child, $subdocument) = @_;
   return unless defined $child;
   if (defined $subdocument) {
      $subdocument->{owning_node} = $self;
   } else {
      $child->{parent} = $self;
   }
   push @{$self->{children}}, [$child, $subdocument];
   return $child;
}

=head2 has_oob, no_oob, set_oob, oob

Each node can optionally have an out-of-band value, or multiple named out-of-band values. This is useful when the nodal structure either has
a generated semantic pole or spans some set of data structures. There is no syntax for out-of-band values (which is why they're out of band).

=cut

sub has_oob { defined $_[0]->{oob} || defined $_[0]->{named_oob} }
sub no_oob {
   delete $_[0]->{oob};
   delete $_[0]->{named_oob};
}
sub set_oob {
   my ($self, $key, $value) = @_;
   if (defined $value) {
      $self->{named_oob}->{$key} = $value;
      return $value;
   }
   $self->{oob} = $key;
   return $key;
}
sub oob {
   my ($self, $key) = @_;
   return $self->{named_oob}->{$key} if defined $key;
   $self->{oob};
}

=head1 LOCATION BY PATH
  - path
  - location

=head1 SEARCHING AND WALKING

=head2 iterate ([field extractor])

The basic nodal structure iterator, this returns an L<Iterator::Records> iterator that does a depth-first walk of the node and its children.

Takes a coderef that, if given a node, returns a list of fields for that node, but if given an undef value, returns an arrayref of the names of those fields. If no coderef is supplied,
a default is used which simply has the node visited as its single column.

=cut

sub iterate {
   my $self = shift;
   my $extractor = shift || \&_default_iterate_extractor;
   
   my $sub = sub {
      my @stack = ([$self]);
      
      sub {
         START_OVER:
         return unless scalar @stack;
         if (not scalar @{$stack[0]}) {
            shift @stack;
            goto START_OVER;
         }
         my $next = shift @{$stack[0]};
         unshift @stack, [$next->children];
         
         return $extractor->($next, scalar (@stack) - 2);
      }
   };
   Iterator::Records->new($sub, $extractor->());
}

sub _default_iterate_extractor {
   my $self = shift;
   my $level = shift;
   
   return ['node'] unless defined $self;
   return [$self];
}

=head2 walk (coderef}

Given a coderef, C<walk> walks the node structure and calls the coderef on each node it finds. It returns a count of the nodes visited.

=cut

sub walk {
   my $self = shift;
   my $coderef = shift;
   return 0 unless $coderef;
   
   my $i = $self->iterate->iter;
   my $count = 0;
   while (my $row = $i->()) {
      $count += 1;
      $coderef->($row->[0]);
   }
   return $count;
}

=head1 INTROSPECTION

=head2 canon_syntax

The canonical string output for a node is its own canonical line (see below) followed by the canonical string output for each of its children in succession,
indented. I prefer an indentation increment of 4.

If a child is inside a subdocument, then the subdocument is asked for its string output.

=cut

sub canon_syntax {
   my ($self, $indent, $esc_char) = @_;
   $indent = 0 unless $indent;
   $esc_char = '' unless defined $esc_char;
   
   my $text = '';
   my $indtext = ' ' x $indent;
   my $child_indent = $indent;
   my $dtext_child_indent = $indent;
   my $line = $esc_char . $self->canon_line;
   if ($line =~ /\n/) {
      $line =~ s/\n/\n$indtext/g;
   }
   
   if ($self->{invisible}) {
   } elsif ($self->{has_dtext_children}) {
      $text = $indtext . $line . " ";
      $child_indent = $indent + 4;
      $dtext_child_indent = $indent + length ($line) + 1;
   } else {
      $text = $indtext . $line . "\n";
      $child_indent = $indent + 4;
   }
   #$text = $indtext . $line . "\n" unless $self->{invisible};
   #$child_indent = $indent + 4 unless $self->{invisible};
   my $first_child = 1;
   
   foreach my $child (@{$self->{children}}) {
      my ($child_node, $subdoc) = @$child;
      
      my $child_text = '';
      my $local_indent = $child_indent;
      $local_indent = $dtext_child_indent if $child_node->{parsed_from_dtext};
      
      if ($child_node->is_tagless and not $child_node->invisible) {
         if ($child_node->{subdoc_type0} eq 'code') {
            $child_text .= ref $child_node->{text} ? $child_node->{text}->extract_string (indent=>$local_indent)
                                                      : length ($child_node->{text}) ? ' ' x $local_indent . $child_node->{text} . "\n" : '';
            if ($child_node->{close_bracket}) {
               $child_text .= $indtext . $child_node->{close_bracket} . "\n";
            }
         } else { # Any other text node type (probably)
         #if ($child_node->{subdoc_type0} eq 'text' || $child_node->{subdoc_type0} eq 'blocktext' || $child_node->{subdoc_type0} eq 'textplus') {
            if (ref $child_node->{text}) {
               $child_text .= $child_node->{text}->extract_string (indent=>$local_indent);
               $child_text = substr ($child_text, $local_indent) if $first_child and $child_node->{parsed_from_dtext};
            } elsif (defined $child_node->{text} && $child_node->{text} eq "\n") {
               $child_text .= "\n";
            } else {
               if ($first_child and $child_node->{parsed_from_dtext}) {
                  $child_text .= $child_node->{text};
               } else {
                  $child_text .= ' ' x $local_indent . $child_node->{text};
               }
            }
         }
      } else {
         $child_text .= "\n" if not $self->{parent} and not $first_child and $self->{invisible}; # Invisible tags space their children (provisional rule - not sure how universal it will prove)   
         $child_text .= $child_node->canon_syntax ($local_indent, $child_node->{esc_char});
         $child_text = substr ($child_text, $local_indent) if $first_child and $child_node->{parsed_from_dtext};
      }
      $first_child = 0;
      $text .= $child_text;
   }
   $text;
}

=head2 debug_structure

=cut

sub debug_structure {
   my ($self, $indent) = @_;
   $indent = 0 unless $indent;
   
   my $text = ' ' x $indent . $self->debug_line . "\n";
   
   foreach my $child (@{$self->{children}}) {
      my ($child_node, $subdoc) = @$child;
      
      $text .= $child_node->debug_structure ($indent + 2);
   }
   $text;
}

sub debug_hash {
   my $self = shift;
   my $text = "Node attributes:\n";
   foreach my $attr (sort keys %$self) {
      $text .= '  ' . $attr . ': ' . (defined $self->{$attr} ? $self->{$attr} : '(undef)') . "\n";
   }
   $text;
}

sub debug_line {
   my $self = shift;
   
   my $line = $self->tag || '';
   $line = '(invis)' if $self->invisible;
   $line = '(sep)' if $self->{separator};
   if ($self->is_sigiled) {
      $line = $self->sigil;
   } elsif (defined $self->sigil) {
      $line .= ' ' . $self->sigil;
   }

   my $dtext = $self->dtext;
   if ($dtext) {
      $line .= ' ' if $line;
      if (not $self->{separator}) {
         $line .= '(text ' . length($dtext) . ' char(s)';
         if ($dtext =~ /\n/) {
            $line .= ', ' . scalar (split /\n/, $dtext) . ' lines';
         }
         $line .= ')'
      }
   }
   
   return $line;
}


=head2 canon_line

The canonical line output for a node is: tag name inparms exparms strings codesegs sigil text/comment
These are all single-spaced on the line.

=cut

sub _bracket_match {
   my $b = shift;
   $b =~ tr/{<\(\[/}>)]/;
   $b;
}
sub canon_line {
    my ($self) = @_;
    my $line = '';
    
    my @parts = ();
    if (not $self->is_sigiled and $self->tag ne '') {
      if ($self->{pseudo}) {
         push @parts, $self->{pseudo} . $self->tag . _bracket_match($self->{pseudo});
      } else {
         push @parts, $self->tag;
      }
    }

    if ($self->has_name) {
       push @parts, @{$self->{names}};
    }
    
    if ($self->has_inparms) {
       my @parms = ();
       foreach my $p ($self->inparms) {
          my $v = $self->inparm($p);
          if (ref $v) {
             push @parms, $p;
             next;
          }
          if ($v =~ /\W|['"]/) {
             push @parms, "$p=" . _quote_string_value($v);
          } else {
             push @parms, "$p=$v";
          }
       }
       push @parts, '(' . join (', ', @parms) . ')';
    }
    if ($self->has_exparms) {
       my @parms = ();
       foreach my $p ($self->exparms) {
          my $v = $self->exparm($p);
          if (ref $v) {
             push @parms, $p;
             next;
          }
          if ($v =~ /\W|['"]/) {
             push @parms, "$p=" . _quote_string_value($v);
          } else {
             push @parms, "$p=$v";
          }
       }
       push @parts, '[' . join (', ', @parms) . ']';
    }

    if ($self->has_string) {
       push @parts, map { _quote_string_value ($_) } @{$self->{strings}};
    }
    
    if ($self->has_dcode) {
       foreach my $code (@{$self->{code}}) {
          my ($type, $text) = @$code;
          push @parts, $type . ' ' . $text . ' ' . _code_sigil_match($type);
       }
    }
        
    $line = join (' ', @parts);
    if ($self->has_sigil || $self->has_dtext) { # Even if we didn't come in with a sigil, the canonical line needs one if we have direct text.
       my $sigil = $self->has_sigil ? $self->sigil : ':';
       $line .= ' ' unless $self->is_sigiled || $sigil =~ /^:/; # I think non-colons look better with a space, so that's how the canonical line presents non-colon sigils.
       $line .= $sigil;
       if ($self->code_tag) {
          $line .= ' ' . $self->code_tag;
       }
       if ($self->has_dtext) {
          my $text = $self->dtext;
          $line .= ' ';
          $text =~ s/\n$//;  # Strip the final bit off.
          my $indent_space = ' ' x length($line);
          $text =~ s/\n/\n$indent_space/g;  
          $line .= $text;
       }
    }
        
    $line .= ' ' . $self->comment_type . ' ' . $self->comment if $self->has_comment;

    return $line;
}

sub _code_sigil_match {
    my $sigil = shift;
    return '>' if $sigil eq '<';
    return ']' if $sigil eq '[';
    return ')' if $sigil eq '(';
    return '}';
}

sub _quote_string_value {
    my $value = shift;
    return unless defined $value;
    
    $value =~ s/\n/\\n/g; # Quote any embedded carriage returns
    return '"' . $value . '"' unless $value =~ /"/;
    return "'" . $value . "'" unless $value =~ /'/;
    $value =~ s/"/\\"/g;
    return '"' . $value . '"';
}

=head1 AUTHOR

Michael Roberts, C<< <michael at cpan.org> >>

=head1 BUGS

Please report any bugs or feature requests to C<bug-decl-document at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Decl-Document>.  I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.




=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc Decl::Node


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

1; # End of Decl::Node
