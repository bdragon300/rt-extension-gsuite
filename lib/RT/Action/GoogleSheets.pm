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
in headers. The whole interact logic places into template code.You can work with
automatically preloaded spreadsheet or load it youself in code. See examples 
below.

For more info see README.


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
our $base_url = 'https://sheets.googleapis.com/v4';


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

    $self->{sheet} = RT::Extension::GSuite::Spreadsheet->new(
        request_obj => $req
    );
    # If X-Spreadsheet-Id didn't specified its supposed that user will set it afterwards
    my $spreadsheet_id = $headers{'X-Spreadsheet-Id'};
    if ($spreadsheet_id) {
        unless ($self->{sheet}->Get($spreadsheet_id)) {
            RT::Logger->error(
                '[RT::Extension::GSuite]: Unable to load spreadsheet with id=' . $spreadsheet_id
            );
            return 0;
        }
    } else {
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
        if (ref $cellsref ne 'ARRAY') {
            RT::Logger->error('[RT::Extension::GSuite]: Cannot write $$Cells '.
                'to spreadsheet because it contains non-ARRAYREF value after template exit');
            return 0;
        }
        $self->{sheet}->SetCells($range, $cellsref);
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