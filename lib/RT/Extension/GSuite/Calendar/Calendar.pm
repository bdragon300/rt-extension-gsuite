package RT::Extension::GSuite::Calendar::Calendar;

use 5.010;
use strict;
use warnings;
use Mouse;

use RT::Extension::GSuite::Calendar::EventList;

=head1 NAME

  RT::Extension::GSuite::Calendar::Calendar - Calendar object

=head1 AUTHOR

Igor Derkach, E<lt>gosha753951@gmail.comE<gt>

=cut

extends 'RT::Extension::GSuite::BaseObject';

with qw(RT::Extension::GSuite::Roles::Request);


my @properties = qw(
    kind etag id summary description location timeZone summaryOverride colorId 
    backgroundColor foregroundColor hidden selected accessRole defaultReminders 
    notificationSettings primary deleted conferenceProperties
);

has \@properties => (
    is => 'rw'
);

has +suburl => (
    is => 'rw',
    default => '/calendars/%s'
);


=head1 METHODS

=head2 Get($id) -> 1|0

Get object by id

Parameters:

=over

=item $id - object id

=back

Returns:

1 on success, 0 on fail

=cut

sub Get {
    my $self = shift;
    my $id = shift;

    my $suburl = sprintf $self->suburl, $id;
    my ($content, $res) = $self->_Request(GET => $suburl);

    return (undef) unless ($res->is_success);
    $self->_FillAttributes(%$content);

    return 1;
}


=head2 Events() -> $iterator

Return iterator with events in current calendar

Parameters:

None

Returns:

=over

=item loaded RT::Extension::GSuite::Calendar::EventList object

=back

=cut

sub Events {
    my $self = shift;

    unless ($self->id) {
        die '[RT::Extension::GSuite]: Unable to load related list, because ' .
            'current object has not loaded';
    }

    return RT::Extension::GSuite::Calendar::EventList->new(
        request_obj => $self->request_obj,
        calendar_id => $self->id
    );
}

1;
