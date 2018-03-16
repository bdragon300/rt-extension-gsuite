package RT::Extension::GSuite::Calendar::EventList;

use 5.010;
use strict;
use warnings;
use Mouse;

use RT::Extension::GSuite::Calendar::Event;

=head1 NAME

  RT::Extension::GSuite::Calendar::EventList - List of event objects

=head1 AUTHOR

Igor Derkach, E<lt>gosha753951@gmail.comE<gt>

=cut

with qw(RT::Extension::GSuite::Roles::Request
        RT::Extension::GSuite::Roles::ListResult);

=head1 ATTRIBUTES

=cut

has +suburl => (
    is => 'rw',
    default => '/calendars/%s/events'
);


=head2 calendar_id

Calendar id which obtaining event list belongs to

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
        # https://developers.google.com/calendar/v3/reference/events/list
        # alwaysIncludeEmail => 0,
        # iCalUID => '',
        # maxAttendees => 10,
        # maxResults => 250,
        # orderBy => '',
        # pageToken => '',  # substituted automatically
        # privateExtendedProperty => '',
        # q => '',
        # sharedExtendedProperty => '',
        # showDeleted => 0,
        # showHiddenInvitations => 0,
        # singleEvents => 0,
        # syncToken => '',
        # timeMax => '',
        # timeMin => '',
        # timeZone => '',
        # updatedMin => ''
    } }
);

sub _MakeItem {
    my $self = shift;
    my $data = shift;

    return RT::Extension::GSuite::Calendar::Event->new(
        request_obj => $self->request_obj,
        calendar_id => $self->calendar_id, 
        %$data
    );
}

sub _FetchPage {
    my $self = shift;
    my $nptoken = shift;

    my $suburl = sprintf $self->suburl, $self->calendar_id;
    
    my %params;
    %params = (%params, %{$self->request_params}) if %{$self->request_params};
    $params{pageToken} = $nptoken if $nptoken;
    $suburl .= '?' . join('&', map { $_ . '=' . $params{$_} } keys %params)
        if %params;

    my ($content, $res) = $self->_Request(GET => $suburl);
    
    return (undef) unless ($res->is_success);
    
    return ($content->{items}, $content->{nextPageToken});
}

1;
