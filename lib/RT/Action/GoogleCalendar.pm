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

This action is a part of RT::Extension::GSuite and intended to work with 
Google Calendar. The specified template sets up parameters of action in 
headers. The whole interact logic places into template code. You can work with 
automatically preloaded calendar or load it youself in code. See examples 
below.

Note: initially your calendar is not visible from service account. You must 
share it with this account before work.

=head2 Templates

=head3 Headers

=over

=item * B<X-Calendar-Id> - Optional. Loads calendar with this id into $Calendar 
variable. If empty all variables mentiones above will not be loaded, but 
still be available.

=item * B<X-Service-Account-Name> - Optional. What account name from extension
config to use to log in the Google account. Default is 'default'.

=back

Note: the Action reads X-* headers value "as-is", so you cannot put some code 
there since it will not be executed.

=head3 Variables

The Action preloads following variables available in passed template:

=over

=item * B<$Calendar> -- RT::Extension::GSuite::Calendar::Calendar object. 
Calendar obtained by id specified in B<X-Calendar-Id> template header

=item * B<$CalendarList> -- RT::Extension::GSuite::Calendar::CalendarList 
object. Current account's calendar list (all ones shown on the left panel 
in web interface)

=item * B<$Events> -- RT::Extension::GSuite::Calendar::EventList object 
contained events of $Calendar object.


=head2 Examples

=head3 Read event list descriptions from specified calendar


    X-Calendar-Id: user@example.com

    {
        my @descriptions;
        while (my $e = $Events->Next) {  # Iterate over events
            next unless $e->description;
            push @descriptions, $e->description;
        }

        # Comment out the ticket with text contained  descriptions divided by semicolon
        $Ticket->Comment(
            Content => 'Events description list: ' . join(';', @descriptions));
    }


=head3 Collect summaries of events that meet search criteria

Search for events using ticket subject as search string, next obtain the 
summary from every event found and, finally, push them to a multi-value
CustomField "RelatedEvents".


    {
        my $search = $Ticket->Subject;  # Lets search by subject as query
        my @summaries;
        while (my $cal = $CalendarList->Next) {
            my $events = $cal->GetEvents;  # Obtain events list in current calendar
            $events->request_params->{q} = $search;  # Set 'q' query parameter, see API docs
            while (my $event = $events->Next) {
                push @summaries, $event->summary;
            }
        }

        $Ticket->AddCustomFieldValue(Field => 'RelatedEvents', Value => $_) for @summaries;  # Add every summary text as custom field value
    }


=head3 Push to ticket's Cc all attendees' emails found in all events (including 
deleted). Get events from calendars with given ids only.


    {
        my %attendees;
        my @cal_ids = ('#contacts@group.v.calendar.google.com', 'user@example.com', 's8rhg5an04cd6tr78tt999ardc@group.calendar.google.com');

        foreach my $cal_id (@cal_ids) {
            $Calendar->Get($cal_id);  # Get and load calendar  by id

            my $events = $Calendar->GetEvents;  # Events list
            $events->request_params->{showDeleted} = 'true';  # Mark that we want also see deleted events
            while (my $event = $events->Next) {
                next unless defined $event->{attendees};  # 'attendees' can be absent in response
                $attendees{$_->{email}} = $_->{displayName} for @{$event->{attendees}};  # Collect attendees from current event
            }
        }

        # Now %attendees contains list of unique emails
        # Lets push them to ticket's Cc. But beforehand we have to make some preparations

        # Load RT::Group represents 'Cc' of current ticket
        my $cc_group = $Ticket->RoleGroup('Cc'); 

        foreach my $email (keys %attendees) {
            # Load RT::User in order to obtain principal id. If such email won't found then user will be created
            my $u = RT::User->new($Ticket->CurrentUser);
            $u->LoadOrCreateByEmail($email);

            # And finally add user
            $cc_group->AddMember($u->PrincipalId);
        }
    }


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
    # If X-Calendar-Id didn't specified its supposed that user will set it afterwards
    my $calendar_id = $headers{'X-Calendar-Id'};
    if ($calendar_id) {
        unless ($self->{calendar}->Get($calendar_id)) {
            RT::Logger->error(
                '[RT::Extension::GSuite]: Unable to load calendar with id=' . $calendar_id
            );
            return 0;
        }
    } else {
        RT::Logger->notice(
            "[RT::Extension::GSuite]: Template #" . $self->TemplateObj->id
            . ": X-Calendar-Id header did not specified. You can set calendar id manually before making requests"
        );
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