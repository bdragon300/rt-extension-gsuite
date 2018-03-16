package RT::Action::GoogleCalendar;

use 5.010;
use strict;
use warnings;

use base qw(RT::Action);
use RT::Extension::GSuite qw(load_config load_token store_token check_json_file);
use RT::Extension::GSuite::JWTAuth;
use RT::Extension::GSuite::Request;
use RT::Extension::GSuite::Calendar::CalendarList;
use RT::Extension::GSuite::Calendar::Calendar;


=head1 NAME

C<RT::Action::GoogleCalendar> - Interact with Google Calendar


=head1 AUTHOR

Igor Derkach, E<lt>gosha753951@gmail.comE<gt>


=head1 BUGS

Please report any bugs or feature requests to the L<author|/"AUTHOR">.


=head1 COPYRIGHT AND LICENSE

Copyright 2017 Igor Derkach, E<lt>https://github.com/bdragon300/E<gt>

This program is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.

Request Tracker (RT) is Copyright Best Practical Solutions, LLC.

=cut


#
# Available template headers
#
my @template_headers = (
    'X-Service-Account-Name',
    'X-Calendar-Id'
);


#
# API scopes
#
my @scopes = qw(
    https://www.googleapis.com/auth/calendar
    https://www.googleapis.com/auth/calendar.readonly
);


#
# Base API url
#
my $base_url = 'https://www.googleapis.com/calendar/v3';


sub Prepare {
    my $self = shift;

    # Read config
    my $config = $self->{config} ||= load_config();
    unless ($config) {
        RT::Logger->error('[RT::Extension::GSuite]: Incomplete config in SiteConfig, see README');
        return 0;
    }
    unless ($self->TemplateObj) {
        RT::Logger->error('[RT::Extension::GSuite]: No template passed. Abort.');
        return 0;
    }

    # Parse MIME message headers. Do not evaluate code in value
    my %headers = ();
    my $headers_regex = '(' . join('|', @template_headers) . ')';
    my @lines = split /\n/, $self->TemplateObj->Content;
    foreach my $line (@lines) {
        if ($line =~ /^${headers_regex}[\t ]*:/) {
            my ($h, $v) = map {s/^[\t ]+|[\t ]+$//gr} split(/:/, $line, 2);
            $headers{$h} = $v;
        }
    }
    undef @lines;
    RT::Logger->debug(
        '[RT::Extension::GSuite]: Template headers parsed: ' 
            . join ',', map {$_ . ' => ' . $headers{$_}} keys %headers
    );

    # Load Google service account and obtain its access_token
    my $account_name = $headers{'X-Service-Account-Name'} // 'default';
    unless (exists $config->{GoogleServiceAccounts}->{$account_name}) {
        RT::Logger->error(
            "[RT::Extension::GSuite]: Service account '$account_name' is not found in config"
        );
        return 0;
    }

    my $token = load_token($account_name); # Token may be expired
    unless ($token) {
        unless ($config->{InsecureJsonFile})
        {
            return 0
                unless (check_json_file($self->{config}->{GoogleServiceAccounts}->{$account_name}->{json_file}));
        }
        
        RT::Logger->info(
            "[RT::Extension::GSuite]: Service account '$account_name' not logged in yet, login will be performed"
        );
    }

    # Create objects available in template
    # If X-Calendar-Id didn't specified its supposed that user will set it afterwards
    my $calendar_id = $headers{'X-Calendar-Id'};
    unless ($calendar_id) {
        RT::Logger->notice(
            "[RT::Extension::GSuite]: Template #" . $self->TemplateObj->id
            . ": X-Calendar-Id header did not specified. You can set calendar id manually before making requests"
        );
    }
    my $req = RT::Extension::GSuite::Request->new(
        jwtauth => RT::Extension::GSuite::JWTAuth->new(
            token => $token,
            json_file => $self->{config}->{GoogleServiceAccounts}->{$account_name}->{json_file},
            scopes => \@scopes
        ),
        base_url => $base_url
    );
    unless($req->login()) {
        RT::Logger->error('[RT::Extension::GSuite]: Unable to login');
        return 0;
    }

    $self->{calendar} = RT::Extension::GSuite::Calendar::Calendar->new(
        request_obj => $req
    );
    unless ($self->{calendar}->Get($calendar_id)) {
        RT::Logger->error('[RT::Extension::GSuite]: Unable to load calendar with id=' . $calendar_id);
        return 0;
    }

    $self->{events} = $self->{calendar}->GetEvents();
    $self->{calendar_list} = RT::Extension::GSuite::Calendar::CalendarList->new(
        request_obj => $req
    );

    $self->{tpl_headers} = \%headers;
    $self->{account_name} = $account_name;

    return 1;
}


sub Commit {
    my $self = shift;

    my ($res, $msg) = $self->TemplateObj->Parse(
        TicketObj => $self->TicketObj,
        TransactionObj => $self->TransactionObj,
        Calendar => $self->{calendar},
        CalendarList => $self->{calendar_list},
        Events => $self->{events}
    );
    return 0 unless ($res);

    undef $self->{events};
    undef $self->{calendar};
    undef $self->{calendar_list};

    # Put token to the cache
    store_token(
        $self->{account_name},
        $self->{sheet}->{request}->{jwtauth}->{token}
    );

    return 1;
}

1;