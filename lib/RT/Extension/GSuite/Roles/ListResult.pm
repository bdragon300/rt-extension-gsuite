package RT::Extension::GSuite::Roles::ListResult;

use 5.010;
use strict;
use warnings;
use Mouse::Role;

=head1 NAME

  RT::Extension::GSuite::Roles::ListResult - Role for list responses. Brings
  iteration ability over API list response

=head1 AUTHOR

Igor Derkach, E<lt>gosha753951@gmail.comE<gt>

=cut

requires qw/_MakeItem _FetchPage/;

=head1 ATTRIBUTES

=head2 list_result

ARRAYREF with list API response

=cut

has list_result => (
    is => 'rw'
);


=head2 offset

Offset in list_result attribute for next iterable item

=cut

has offset => (
    is => 'rw',
    default => 0,
    init_arg => undef
);


=head2 _next_page_token

'nextPageToken' value came with current page of results.

See: https://developers.google.com/calendar/v3/pagination

=cut

has _next_page_token => (
    is => 'rw'
);


=head2 _iter_end

Becomes 1 when iteration reached the end

=cut

has _iter_end => (
    is => 'rw',
    default => 0
);


=head2 page

Page counter. Initial value is 0.

=cut

has page => (
    is => 'rw',
    default => 0
);


=head1 METHODS

=head2 Next() -> $object|undef

Iterate forward over list response. Automatically fetches next page when
current one is over.

Some methods must be implemented in object for which current class acts as role:

=over

=item _FetchPage($next_page_token) -> ($results, $next_page_token) -- fetch 
next page of results. Must receive 'nextPageToken' value comes with current
page. If nextPageToken is undef then the first page must be returned. Returns
array with results ARRAYREF and next nextPageToken if any.

=item _MakeItem($dict) -> $object -- build item object from dict data

=back

Parameters:

None

Returns:

=over

=item $object

=item undef -- means not items left

=back

=cut

sub Next {
    my $self = shift;

    return (undef) if $self->_iter_end;  # Last page

    my $r = $self->list_result;
    my $item = $r && $r->[$self->offset];
    $self->offset($self->offset + 1);

    unless (defined $item) {  # First/Next page
        if ( $self->page && ! $self->_next_page_token) {
            $self->_iter_end(1);
            return (undef);
        }
        my $t;
        # my $t = $self->_next_page_token;
        # $self->_iter_end(defined $t && $t eq '');
        ($r, $t) =
            $self->_FetchPage($self->_next_page_token);
        $self->list_result($r);
        $self->_next_page_token($t);
        $self->page($self->page + 1);

        $item = $r && $r->[0];
        $self->offset(1);
        $self->_iter_end(1) unless ($t || defined $item);
    }
    
    return $self->_MakeItem($item) if (defined $item);

    return (undef);
}


=head2 Clear() -> none

Clear internal state. After this function call the iteration starts from the
first element again

Parameters:

None

Returns:

None

=cut

sub Clear {
    my $self = shift;

    $self->offset(0);
    $self->_next_page_token(undef);
    $self->list_result(undef);
    $self->_iter_end(0);
    $self->page(0);
}

1;
