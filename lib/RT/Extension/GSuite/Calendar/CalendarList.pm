package RT::Extension::GSuite::Calendar::CalendarList;

use 5.010;
use strict;
use warnings;
use Mouse;

use RT::Extension::GSuite::Calendar;

=head1 NAME

  RT::Extension::GSuite::Calendar::CalendarList - List of calendar objects

=head1 AUTHOR

Igor Derkach, E<lt>gosha753951@gmail.comE<gt>

=cut

with qw(RT::Extension::GSuite::Roles::Request
        RT::Extension::GSuite::Roles::ListResult);


=head1 ATTRIBUTES

=cut

has +suburl => (
    is => 'rw',
    default => '/users/me/calendarList'
);


=head2 request_params

Hashref with parameters passes in url of API request

See: https://developers.google.com/calendar/v3/reference/calendarList/list

=cut

has request_params => (
    is => 'rw',
    isa => 'HashRef',
    required => 1,
    auto_deref => 1,
    default => sub { {  # Coderef instead of hashref, see Mouse docs
        # https://developers.google.com/calendar/v3/reference/calendarList/list
        # maxResults => 100,
        # minAccessRole => '',
        # pageToken => '',  # substituted automatically
        # showDeleted => 0,
        # showHidden => 0,
        # syncToken => ''
    } }
);

sub _MakeItem {
    my $self = shift;
    my $data = shift;

    return RT::Extension::GSuite::Calendar->new(
        request_obj => $self->request_obj,
        %$data
    );
}

sub _FetchPage {
    my $self = shift;
    my $nptoken = shift;

    my $suburl = $self->suburl;

    my %params = %{$self->request_params};
    $params{pageToken} = $nptoken if $nptoken;
    
    my ($content, $res) = $self->_Request(GET => $suburl, \%params);

    return (undef) unless ($res->is_success);
    
    return ($content->{items}, $content->{nextPageToken});
}

1;
