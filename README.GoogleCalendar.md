# RT::Action::GoogleCalendar

## Summary

This action is a part of RT::Extension::GSuite and intended to work with 
Google Calendar. The specified template sets up parameters of action
in headers. The whole interact logic places into template code. You can work with automatically preloaded calendar or load it youself in code. See examples below.

Note: initially your calendar is not visible from service account. You must share it with this account before work.

## Templates

### Headers

* **X-Calendar-Id** - Optional. Loads calendar with this id into ```$Calendar``` variable. If empty all variables mentiones above will not be loaded, but still be available.
* **X-Service-Account-Name** - Optional. What account name from extension
config to use to log in the Google account. Default is 'default'.

Note: the Action reads X-* headers value "as-is", so you cannot put some code there since it will not be executed.

### Variables

The Action preloads following variables available in passed template:

* ```$Calendar``` -- RT::Extension::GSuite::Calendar object. Calendar obtained by id specified in ```X-Calendar-Id``` template header
* ```$CalendarList``` -- RT::Extension::GSuite::Calendar::CalendarList object. Current account's calendar list (all ones shown on the left panel in web interface)
* ```$Events``` -- RT::Extension::GSuite::Calendar::EventList object contained events of ```$Calendar``` object.

### Object methods, attributes and documentation

Calendar object:
```
perldoc <RTBASEPATH>/local/plugins/RT-Extension-GSuite/lib/RT/Extension/GSuite/Calendar/Calendar.pm
```

CalendarList object:
```
perldoc <RTBASEPATH>/local/plugins/RT-Extension-GSuite/lib/RT/Extension/GSuite/Calendar/CalendarList.pm
```

Event object:
```
perldoc <RTBASEPATH>/local/plugins/RT-Extension-GSuite/lib/RT/Extension/GSuite/Calendar/Event.pm
```

EventList object:
```
perldoc <RTBASEPATH>/local/plugins/RT-Extension-GSuite/lib/RT/Extension/GSuite/Calendar/EventList.pm
```

List operations:
```
perldoc <RTBASEPATH>/local/plugins/RT-Extension-GSuite/lib/RT/Extension/GSuite/Roles/ListResult.pm
```

## Examples

### Read event list descriptions from specified calendar

```
X-Calendar-Id: user@example.com

{
    my @descriptions;
    while (my $e = $Events->Next) {  # Iterate over events
        next unless $e->description;
        push @descriptions, $e->description;
    }
    $Ticket->Comment(Content => 'Events description list: ' . join(';', @descriptions));  # Comment out the ticket with text contained  descriptions divided by semicolon
}
```

### Read start datetime of all instances of recurring events

```
X-Calendar-Id: user@example.com

{
    my %instances;  # Summary => [dateTime]
    while (my $e = $Events->Next) {  # Iterate over events
        my $instances = $e->Instances;
        while (my $inst = $instances->Next) {
            next unless $inst->start;
            $instances{$inst->summary} = [] unless exists $instances{$inst->summary};
            push %instances{$inst->summary}, $inst->start->{dateTime};
        }
    }
    my @msg = map { $_ . ': '. join ',', @{$instances{$_}} } keys %instances;
    $Ticket->Comment(Content => 'Recurring events: ' . join('; ', @msg) );  # Comment out the ticket with text contained  descriptions divided by semicolon
}
```

### Collect summaries of events that meet search criteria

Search for events using ticket subject as search string, next obtain the summary from every event found and, finally, push them to a multi-value CustomField "RelatedEvents".

```
{
    my $search = $Ticket->Subject;  # Lets search by subject as query
    my @summaries;
    while (my $cal = $CalendarList->Next) {
        my $events = $cal->Events;  # Obtain events list in current calendar
        $events->request_params->{q} = $search;  # Set 'q' query parameter, see API docs
        while (my $event = $events->Next) {
            push @summaries, $event->summary;
        }
    }

    $Ticket->AddCustomFieldValue(Field => 'RelatedEvents', Value => $_) for @summaries;  # Add every summary text as custom field value
}
```

### Push to ticket's Cc all attendees' emails found in all events (including deleted). Get events from calendars with given ids only.

```
{
    my %attendees;
    my @cal_ids = ('#contacts@group.v.calendar.google.com', 'user@example.com', 's8rhg5an04cd6tr78tt999ardc@group.calendar.google.com');

    foreach my $cal_id (@cal_ids) {
        $Calendar->Get($cal_id);  # Get and load calendar  by id

        my $events = $Calendar->Events;  # Events list
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
```


# Author

Igor Derkach, <gosha753951@gmail.com>


# Bugs

Please report any bugs or feature requests to the author.


# Copyright and license

Copyright 2017 Igor Derkach, <https://github.com/bdragon300/>

This program is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.

Request Tracker (RT) is Copyright Best Practical Solutions, LLC.
