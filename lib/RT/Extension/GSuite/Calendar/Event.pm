package RT::Extension::GSuite::Calendar::Event;

use 5.010;
use strict;
use warnings;
use Mouse;

use RT::Extension::GSuite::Calendar::Calendar;

=head1 NAME

  RT::Extension::GSuite::Calendar::Event - Event object

=head1 AUTHOR

Igor Derkach, E<lt>gosha753951@gmail.comE<gt>

=cut

extends 'RT::Extension::GSuite::BaseObject';

with qw(RT::Extension::GSuite::Roles::Request);


=head1 ATTRIBUTES

=cut

my @properties = qw(
    kind etag id status htmlLink created updated summary description location 
    colorId creator organizer start end endTimeUnspecified recurrence 
    recurringEventId originalStartTime transparency visibility iCalUID sequence 
    attendees attendeesOmitted extendedProperties hangoutLink conferenceData 
    gadget anyoneCanAddSelf guestsCanInviteOthers guestsCanModify 
    guestsCanSeeOtherGuests privateCopy locked reminders source attachments
);

has \@properties => (
    is => 'rw'
);

has +suburl => (
    is => 'rw',
    default => '/calendars/%s/events/%s'
);


=head2 calendar_id

Calendar id which this event belongs to

=cut

has calendar_id => (
    is => 'rw',
    isa => 'Str',
    required => 1
);


=head2 request_params

Hashref with parameters passes in url of API request

https://developers.google.com/calendar/v3/reference/events/get

=cut

has request_params => (
    is => 'rw',
    isa => 'HashRef',
    required => 1,
    auto_deref => 1,
    default => sub { {  # Coderef instead of hashref, see Mouse docs
        # https://developers.google.com/calendar/v3/reference/events/get
        # alwaysIncludeEmail => 0,
        # maxAttendees => 100,
        # timeZone => ''
    } }
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

    my $suburl = sprintf $self->suburl, $self->calendar_id, $id;
    if ($self->request_params) {
        $suburl .= '?' . join('&', 
            map { $_ . '=' . $self->request_params->{$_} } 
            keys %{$self->request_params}
        );
    }
    my ($content, $res) = $self->_Request(GET => $suburl);

    return (undef) unless ($res->is_success);
    $self->_FillAttributes(%$content);

    return 1;
}

=head2 GetCalendar() -> $calendar_object

Return Calendar object which this event belongs to

Parameters:

None

Return:

Loaded RT::Extension::GSuite::Calendar::Calendar object

=cut

sub GetCalendar {
    my $self = shift;

    unless ($self->id) {
        die '[RT::Extension::GSuite]: Unable to load related list, because ' .
            'current object has not loaded';
    }

    my $cal = RT::Extension::GSuite::Calendar::Calendar->new(
        request_obj => $self->request_obj
    );
    $cal->Get($self->calendar_id);
    return $cal;
}

1;