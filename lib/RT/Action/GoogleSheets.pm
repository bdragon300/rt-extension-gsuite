package RT::Action::GoogleSheets;

use 5.010;
use strict;
use warnings;

use base qw(RT::Action);
use RT::Extension::GSuite qw(load_config load_token store_token check_json_file);
use RT::Extension::GSuite::JWTAuth;
use RT::Extension::GSuite::Request;
use RT::Extension::GSuite::Spreadsheet;


=head1 NAME

C<RT::Action::GoogleSheets> - Interact with Google Sheets

=head1 DESCRIPTION

=head2 Summary

This action is intended to work with Google Sheets spreadsheet. The passed 
template sets up parameters of work. Parameters are set by template headers.
The Action uses Google Service Accounts 
(L<https://developers.google.com/identity/protocols/OAuth2ServiceAccount>) so 
you need to create such account and download .json file. Then edit your 
RT_SiteConfig.pm to add account (see below).

You simply specify cells, e.g. "A1:B4" and their values will be loaded to the
$$Cells variable. Similarly you can specify another range, e.g. "C4:C20", 
put values into $$Cells inside template code and spreadsheet will be 
updated by Action afterwards. (Always use this variable with $$ before name)

If you want implement more complex behavior, you can manipulate already 
preloaded spreadsheet object via $Sheet variable.

=head2 Execute sequence

=over

=item * builds context contains JWT auth, request objects and initialized 
Spreadsheet object (headers from passed templates will be used for configuration). 
Authorization will be performed if necessary;

=item * if X-Read-Cells template header is specified, then loads appropriate cell 
values from the spreadsheet and puts them to $$Cells template variable

=item * performs template parsing process (RT parses and executes code inside)

=item * if X-Write-Cells template header is specified, then writes $$Cells 
template variable data to appropriate cells in the spreadsheet

=back

=head2 Templates

=head3 Headers:

=over

=item * B<X-Spreadsheet-Id> - Required. Google spreadsheet id. See: 
L<https://developers.google.com/sheets/api/guides/concepts#spreadsheet_id>

=item * B<X-Service-Account-Name> - Optional. Determine what account use. Default
is 'default'.

=item * B<X-Read-Cells> - Optional. If set must contain cell range in A1 notation,
e.g. A1:B4. These cells will be read before template parse and their values will
be put into $$Cells variable inside template context. Default API options will be
used (majorDimension='ROWS'. i.e array of rows that contains cells).

=item * B<X-Write-Cells> - Optional. If set must contain cell range in A1 notation,
e.g. A1:B4. These cells will be filled from $$Cells variable after template parse
process finished and code evaluated. Default API options will be used.

=back

=head3 Template context:

=over

=item * B<$$Cells> - REF to ARRAYREF. Contains cells data preliminary read (if 
set, empty array otherwise) and data that will be written afterwards (if set, 
ignored otherwise)

=item * B<$Sheet> - RT::Extension::GSuite::Spreadsheet object of current spreadsheet.

=back

=head2 Examples

=head3 Simple read

=begin text

X-Spreadsheet-Id: a8fdc205a9f19cc1c7507a60c4f01b13d11d7fd0a
X-Read-Cells: A1:B1

{
    $Ticket->AddCustomFieldValue(Field=>12, Value=>$$Cells->[0]->[0]);
    $Ticket->AddCustomFieldValue(Field=>15, Value=>$$Cells->[0]->[1]);
}

=end text

=head3 Simple read/write

=begin text

X-Spreadsheet-Id: a8fdc205a9f19cc1c7507a60c4f01b13d11d7fd0a
X-Read-Cells: A1
X-Write-Cells: Analytics!C3:D4

{
    $Ticket->AddCustomFieldValue(Field=>12, Value=>$$Cells->[0]->[0]);
    
    $$Cells = [["Debet", "Credit"], [100, 1000]]; #[[C3:C4], [D3:D4]];
}

=end text

=head3 Use $Sheet

=begin text

X-Spreadsheet-Id: a8fdc205a9f19cc1c7507a60c4f01b13d11d7fd0a

{
    # Same as previous example but we can change valueRenderOption api option and
    #  get cell formula instead of value
    $Ticket->AddCustomFieldValue(
        Field=>"A1 formula",
        Value=>$Sheet->GetCell("A1", valueRenderOption=>'FORMULA')
    );
    
    # Cells fills as same as previous example, but we changed
    #  majorDimension api parameter to 'COLUMNS'
    # See: https://developers.google.com/sheets/api/reference/rest/v4/spreadsheets.values/get

    my $data = [["Debet", 100], ["Credit", 1000]]; #[[C3:D3], [C4:D4]];
    $Sheet->SetCells("Analytics!C3:D4", $data, majorDimension=>'COLUMNS');
}

=end text

=head1 AUTHOR

Igor Derkach, E<lt>gosha753951@gmail.comE<gt>


=head1 BUGS

Please report any bugs or feature requests to the L<author|/"AUTHOR">.


=head1 COPYRIGHT AND LICENSE

Copyright 2015 Igor Derkach, E<lt>https://github.com/bdragon300/E<gt>

This program is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.

Request Tracker (RT) is Copyright Best Practical Solutions, LLC.

=cut


=head1 VARIABLES

=cut


=head2 @template_headers

List of available template headers

=cut

my @template_headers = (
    'X-Service-Account-Name',
    'X-Spreadsheet-Id',
    'X-Read-Cells',
    'X-Write-Cells'
);

=head2 @scopes

List of needed API scopes to interact with sheets api for read/write

=cut

our @scopes = qw(
    https://www.googleapis.com/auth/drive
    https://www.googleapis.com/auth/drive.readonly
    https://www.googleapis.com/auth/spreadsheets
    https://www.googleapis.com/auth/spreadsheets.readonly
);

=head2 $base_url

Base API url

=cut

our $base_url = 'https://sheets.googleapis.com/v4/spreadsheets';



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
        unless ($config->{UnsecuredJsonFile})
        {
            return 0
                unless (check_json_file($self->{config}->{GoogleServiceAccounts}->{$account_name}->{json_file}));
        }
        
        RT::Logger->info(
            "[RT::Extension::GSuite]: Service account '$account_name' not logged in yet, login will be performed"
        );
    }

    # Create spreadsheet
    # If X-Spreadsheet-Id didn't specified its supposed that user will set it afterwards
    my $spreadsheet_id = $headers{'X-Spreadsheet-Id'};
    unless ($spreadsheet_id) {
        if ($headers{'X-Read-Cells'} || $headers{'X-Write-Cells'}) {
            RT::Logger->warning(
                "[RT::Extension::GSuite]: Template #" . $self->TemplateObj->id
                . ": X-Spreadsheet-Id header did not specified, X-Read-Cells and X-Write-Cells would not work"
            );
        } else {
            RT::Logger->notice(
                "[RT::Extension::GSuite]: Template #" . $self->TemplateObj->id
                . ": X-Spreadsheet-Id header did not specified. You can set spreadsheet id manually before making requests"
            );
        }
    }
    $self->{sheet} = RT::Extension::GSuite::Spreadsheet->new(
        spreadsheet_id => $spreadsheet_id,
        request => RT::Extension::GSuite::Request->new(
            jwtauth => RT::Extension::GSuite::JWTAuth->new(
                token => $token,
                json_file => $self->{config}->{GoogleServiceAccounts}->{$account_name}->{json_file},
                scopes => \@scopes
            ),
            base_url => $base_url
        )
    );
    $self->{tpl_headers} = \%headers;
    $self->{account_name} = $account_name;

    return 1;
}


sub Commit {
    my $self = shift;

    my $cellsref = [];
    my $range = undef;

    # X-Read-Cells
    if ($range = $self->{tpl_headers}->{'X-Read-Cells'}) {
        @$cellsref = $self->{sheet}->GetCells($range);
    }

    my ($res, $msg) = $self->TemplateObj->Parse(
        TicketObj => $self->TicketObj,
        TransactionObj => $self->TransactionObj,
        Sheet => $self->{sheet},
        Cells => \$cellsref
    );
    return 0 unless ($res);

    # X-Write-Cells
    if ($range = $self->{tpl_headers}->{'X-Write-Cells'}) {
        my $res = $self->{sheet}->SetCells($range, $cellsref);
        return 0 unless ($res->is_success);
    }
    undef $cellsref;

    # Put token in cache
    store_token(
        $self->{account_name},
        $self->{sheet}->{request}->{jwtauth}->{token}
    );

    return 1;
}

1;