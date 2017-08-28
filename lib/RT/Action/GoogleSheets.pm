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

This action is a part of RT::Extension::GSuite and intended to work with 
Google Sheets spreadsheet. The specified template sets up parameters of action
in headers. The whole interact logic places into template code.

You can work with spreadsheet in two ways: simple and complex. 

Simple: you specify cells by a header, e.g. "X-Read-Cells: A1:B4" and their 
values will be loaded to the $$Cells variable. Similarly you can specify 
another range, e.g. "X-Write-Cells: C4:C20", put values into $$Cells inside 
template code and spreadsheet will be updated by Action afterwards. (Always 
use this variable with $$ before name).

If you want to implement more complex behavior, you can manipulate previously 
loaded RT::Extension::GSuite::Spreadsheet object via $Sheet variable.

=head2 Execute sequence

=over

=item * build context contained initialized objects: JWT auth, Request, 
Spreadsheet. (headers from given templates will be used for configuration). 
Authorization will be performed if necessary;

=item * if X-Read-Cells template header is specified, then load appropriate 
cell values from the spreadsheet and put result to the $$Cells variable

=item * perform standard template parsing process

=item * if X-Write-Cells template header is specified, then write the $$Cells
data to the appropriate cells in the spreadsheet

=back

=head2 Templates

=head3 Headers

=over

=item * B<X-Spreadsheet-Id> - Optional, but usually set. Google spreadsheet 
id. If not set then you have to load spreadsheet manually using 
$Sheet->SetSpreadsheetId(id). Also you can't use another headers such 
X-Read-Cells in that case. Such behavior is suitable when spreadsheet id 
calculates during template code execution.
See: 
L<https://developers.google.com/sheets/api/guides/concepts#spreadsheet_id>

=item * B<X-Service-Account-Name> - Optional. What account name from extension
config to use to log in the Google account. Default is 'default'.

=item * B<X-Read-Cells> - Optional. Must contain cell range in A1 notation,
e.g. A1:B4. Values of these cells will be read before the template 
parsing and put into $$Cells variable inside template context. Default API 
options will be used (for instance, majorDimension='ROWS').

=item * B<X-Write-Cells> - Optional. Must contain cell range in A1 notation,
e.g. A1:B4. These cells will be filled out from $$Cells variable content 
just after the template parse process has finished and the code has evaluated.
Default API options will be used.

=back

Note: the Action obtains X-* headers value "as-is", before the some code 
executes. Use $Sheet variable inside the template code if you want more complex
behavior.

=head3 Template context

=over

=item * B<$$Cells> - REF to ARRAYREF. Contains cells data preliminary read 
(empty array if X-Read-Cells is not set) and data that will be written 
afterwards (ignores if X-Write-Cells is not set).

=item * B<$Sheet> - RT::Extension::GSuite::Spreadsheet object of the current
spreadsheet.

=back

=head2 Examples

=head3 Simple read

    X-Spreadsheet-Id: a8fdc205a9f19cc1c7507a60c4f01b13d11d7fd0a
    X-Read-Cells: A1:B1

    {
        $Ticket->AddCustomFieldValue(Field=>12, Value=>$$Cells->[0]->[0]); # A1
        $Ticket->AddCustomFieldValue(Field=>15, Value=>$$Cells->[0]->[1]); # B1
    }

=head3 Simple read/write

    X-Spreadsheet-Id: a8fdc205a9f19cc1c7507a60c4f01b13d11d7fd0a
    X-Read-Cells: A1
    X-Write-Cells: Analytics!A1:B2

    {
        $Ticket->AddCustomFieldValue(Field=>12, Value=>$$Cells->[0]->[0]); # A1
        
        $$Cells = [["Debet", "Credit"], [100, 1000]];
        # Result:
        # -----------------------
        # |   |   A   |   B     |
        # -----------------------
        # | 1 | Debet | Credit  |
        # -----------------------
        # | 2 | 100   | 1000    |
        # -----------------------
    }

=head3 Using $Sheet

    X-Spreadsheet-Id: a8fdc205a9f19cc1c7507a60c4f01b13d11d7fd0a

    {
        # Same as previous example but we can change valueRenderOption api option and
        #  get cell formula instead of value
        $Ticket->AddCustomFieldValue(
            Field=>"A1 formula",
            Value=>$Sheet->GetCell("A1", valueRenderOption=>'FORMULA')
        );
        
        # Cells filled as same as previous example, but we changed
        #  majorDimension api parameter to 'COLUMNS'
        # See: https://developers.google.com/sheets/api/reference/rest/v4/spreadsheets.values/get

        my $data = [["Debet", "Credit"], [100, 1000]];
        $Sheet->SetCells("Analytics!A1:B2", $data, majorDimension=>'COLUMNS');
        # Result:
        # -----------------------
        # |   |   A    |   B    |
        # -----------------------
        # | 1 | Debet  | 100    |
        # -----------------------
        # | 2 | Credit | 1000   |
        # -----------------------
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
    'X-Spreadsheet-Id',
    'X-Read-Cells',
    'X-Write-Cells'
);


#
# List of needed API scopes to interact with sheets api for read/write
#
our @scopes = qw(
    https://www.googleapis.com/auth/drive
    https://www.googleapis.com/auth/drive.readonly
    https://www.googleapis.com/auth/spreadsheets
    https://www.googleapis.com/auth/spreadsheets.readonly
);


#
# Base API url
#
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
        unless ($config->{InsecureJsonFile})
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
    unless($self->{sheet}->{request}->login()) {
        RT::Logger->error('[RT::Extension::GSuite]: Unable to login');
        return 0;
    }
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

    # Put token to the cache
    store_token(
        $self->{account_name},
        $self->{sheet}->{request}->{jwtauth}->{token}
    );

    return 1;
}

1;