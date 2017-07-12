package RT::Extension::GSuite::Spreadsheet;

use 5.010;
use strict;
use warnings;

use Carp;


=head1 NAME

  RT::Extension::GSuite::Spreadsheet - Spreadsheet interface to spreadsheet in 
  Google Sheets

=head1 DESCRIPTION

  This package abstracts working with spreadsheet. It can be used inside 
  RT Templates to interact with one spreadsheet.

=head1 AUTHOR

Igor Derkach, E<lt>gosha753951@gmail.comE<gt>

=head1 METHODS

=head2 new(spreadsheet_id, request)

Parameters:

=over

=item spreadsheet_id - spreadsheet id. Can be omitted but must be set via 
SetSpreadsheetId before making requests

=item request - RT::Extension::GSuite::Request object as request machinery

=back

=cut

sub new {
    my $class = shift;
    my %args = (
        spreadsheet_id => undef,
        request => undef,
        @_
    );

    $args{request} or die 'Empty request param';

    my $self = bless {%args}, $class;

    $self->{initial_base_url} = $args{request}->{base_url};
    $self->SetSpreadsheetId($args{spreadsheet_id});

    return $self;
}


=head2 SetSpreadsheetId(spreadsheet_id)

Parameters:

=over

=item spreadsheet_id

=back

=cut

sub SetSpreadsheetId {
    my ($self, $spreadsheet_id) = @_;

    $self->{request}->{base_url} = $self->{initial_base_url};
    $self->{request}->{base_url} .= '/' . $self->{spreadsheet_id}
        if $self->{spreadsheet_id};
}


=head2 GetCells(range, API_OPTIONS)

Returns a range of values from a spreadsheet.

Parameters:

=over

=item range - cell range to retrieve in A1 notation

=item API_OPTIONS - named parameters with api request options. See function code

=back

Returns:

=over

=item In list context returns obtained cell values as array

=item In scalar context returns Furl::Response object

=back

See also:

https://developers.google.com/sheets/api/reference/rest/v4/spreadsheets.values/get

https://developers.google.com/sheets/api/guides/concepts#a1_notation

=cut

sub GetCells {
    my $self = shift;
    my $range = shift;
    my %api_args = (
        majorDimension => 'ROWS',
        valueRenderOption => 'FORMATTED_VALUE',
        dateTimeRenderOption => 'SERIAL_NUMBER',
        @_
    );

    unless ($self->_match_a1_cell_range($range)) {
        RT::Logger->error(
            "[RT::Extension::GSuite]: Incorrect range passed: $range"
        );
        return ();
    }

    my $url = 
        '/values/' 
        . $range 
        . '?' 
        . join('&', map { $_ . '=' . $api_args{$_} } keys %api_args);
    my ($content, $res) = $self->_request(
        GET => $url
    );

    my $vals = [];
    if ($res->is_success) {
        if (ref $content eq 'HASH') {
            $vals = $content->{'values'} // [];
        }
    }

    return wantarray ? @$vals : $res;
}


=head2 SetCells(range, values, API_OPTIONS)

Sets values in a range of a spreadsheet.

Parameters:

=over

=item range - cell range to set in A1 notation

=item values - ARRAYREF with data. Structure depends on majorDimension api 
option whose default value is "ROWS".

=item API_OPTIONS - named parameters with api request options. See function code

=back

Returns:

=over

=item In list context returns obtained cell values as array (if includeValuesInResponse
api option is set), empty list otherwise

=item In scalar context returns Furl::Response object

=back

See also:

https://developers.google.com/sheets/api/reference/rest/v4/spreadsheets.values/get

https://developers.google.com/sheets/api/guides/concepts#a1_notation

=cut

sub SetCells {
    my $self = shift;
    my $range = shift;
    my $values = shift;
    my %api_args = (
        majorDimension => 'ROWS',
        valueInputOption => 'USER_ENTERED',
        includeValuesInResponse => 0,
        responseValueRenderOption => 'FORMATTED_VALUE',
        responseDateTimeRenderOption => 'SERIAL_NUMBER',
        @_
    );

    my $md = delete $api_args{majorDimension};

    unless ($self->_match_a1_cell_range($range)) {
        RT::Logger->error(
            "[RT::Extension::GSuite]: Incorrect range passed: $range"
        );
        return ();
    }

    my $request_body = {
        'majorDimension' => $md,
        'range' => $range,
        'values' => $values
    };
    my $url = 
        '/values/' 
        . $range 
        . '?' 
        . join('&', map { $_ . '=' . $api_args{$_} } keys %api_args);
    my ($content, $res) = $self->_request(
        PUT => $url,
        $request_body
    );

    my $vals = [];
    if ($res->is_success) {
        if (ref $content eq 'HASH') {
            $vals = $content->{'updatedData'}->{'values'} // [];
        }
    }

    return wantarray ? @$vals : $res;
}


=head2 GetCell(addr, API_OPTIONS)

Returns value of one cell in given address in the spreadsheet

Parameters:

=over

=item addr - cell address in A1 notation

=item API_OPTIONS - named parameters with api request options. See function code

=back

Returns:

Cell value or undef

=cut

sub GetCell {
    my $self = shift;
    my $addr = shift;
    my %api_args = (
        majorDimension => 'ROWS',
        valueRenderOption => 'FORMATTED_VALUE',
        dateTimeRenderOption => 'SERIAL_NUMBER',
        @_
    );

    unless ($self->_match_a1_cell($addr)) {
        RT::Logger->error(
            "[RT::Extension::GSuite]: Incorrect cell address: $addr"
        );
    }

    my @vals = $self->GetCells($addr, %api_args);
    return @vals ? $vals[0][0] : (undef);
}


=head2 SetCell(addr, API_OPTIONS)

Returns value of one cell in given address in the spreadsheet

Parameters:

=over

=item addr - cell address in A1 notation

=item value - cell value

=item API_OPTIONS - named parameters with api request options. See function code

=back

Returns:

Cell value (if includeValuesInResponse api option is set), empty string otherwise,
or undef on error

=cut

sub SetCell {
    my $self = shift;
    my $addr = shift;
    my $value = shift;
    my %api_args = (
        majorDimension => 'ROWS',
        valueInputOption => 'USER_ENTERED',
        includeValuesInResponse => 0,
        responseValueRenderOption => 'FORMATTED_VALUE',
        responseDateTimeRenderOption => 'SERIAL_NUMBER',
        @_
    );

    unless ($self->_match_a1_cell($addr)) {
        RT::Logger->error(
            "[RT::Extension::GSuite]: Incorrect cell address: $addr"
        );
    }

    my @vals = $self->SetCells($addr, [[$value]], %api_args);
    return @vals ? $vals[0][0] : (undef);
}


sub _request {
    my $self = shift;

    unless ($self->{spreadsheet_id}) {
        RT::Logger->warning(
            '[RT::Extension::GSuite]: Spreadsheet id not set, API call possibly will fail'
        );
    }

    my ($content, $res) = $self->{request}->request(@_);
    unless ($res->is_success) {
        RT::Logger->error(
            '[RT::Extension::GSuite]: Google API request failed: ' 
            . $res->request->request_line . ' => ' . $res->status 
            . ': ' . $res->message);
    }

    return ($content, $res);
}


sub _match_a1_cell_range {
    shift if ref $_[0];
    $_[0] =~ /^([^!]+!)?([A-Za-z]+[1-9][0-9]*:)?([A-Za-z]+[1-9][0-9]*)$/;
}


sub _match_a1_cell {
    shift if ref $_[0];
    $_[0] =~ /^([A-Za-z]+[1-9][0-9]*)$/;
}

1;
