package RT::Extension::GSuite::Spreadsheet;

use 5.010;
use strict;
use warnings;
use Mouse;

use RT::Extension::GSuite::Spreadsheet::ValueRange;


=head1 NAME

  RT::Extension::GSuite::Spreadsheet - Interface to a Google Sheets spreadsheet

=head1 AUTHOR

Igor Derkach, E<lt>gosha753951@gmail.comE<gt>

=cut

extends 'RT::Extension::GSuite::BaseObject';

with qw(RT::Extension::GSuite::Roles::Request);


=head1 ATTRIBUTES

=head2 spreadsheet resource attributes

See: https://developers.google.com/sheets/api/reference/rest/v4/spreadsheets

=cut

my @properties = qw(
    spreadsheetId properties sheets namedRanges spreadsheetUrl
    developerMetadata
);

has \@properties => (
    is => 'rw'
);

has +suburl => (
    is => 'rw',
    default => '/spreadsheets/%s'
);


=head1 METHODS

=head2 Get($id) -> boolean

Get object by id

Parameters:

=over

=item $id - object id

=back

Returns:

Whether operation was successfull

=cut

sub Get {
    my $self = shift;
    my $id = shift;

    my $suburl = sprintf $self->suburl, $id;
    my ($content, $res) = $self->_Request(GET => $suburl);

    return (undef) unless ($res->is_success);
    $self->_FillAttributes(%$content);

    return 1;
}


=head2 Reload() -> boolean

Reload current object previoiusly loaded by the same id.
Useful e.g. for refresh object after modification

Parameters:

None

Return:

Whether operation was successfull

=cut

sub Reload {
    my $self = shift;

    unless ($self->spreadsheetId) {
        die '[RT::Extension::GSuite]: Unable to reload Spreadsheet object ' .
        'with empty spreadsheetId';
    }

    $self->Get($self->spreadsheetId);
}


=head2 ValueRange($range => undef) -> ValueRange object

Return ValueRange object that represents some range in current spreadsheet. 
If $range specified then also load data to returned object

Parameters:

=over

=item $range -- Optional. Cell range in A1 notation

=back

Returns:

RT::Extension::GSuite::Spreadsheet::ValueRange object

=cut

sub ValueRange {
    my $self = shift;
    my $range = shift;

    unless ($self->spreadsheetId) {
        die '[RT::Extension::GSuite]: Unable to load related list, because ' .
            'current object has not loaded';
    }

    my $res = RT::Extension::GSuite::Spreadsheet::ValueRange->new(
        request_obj => $self->request_obj,
        spreadsheetId => $self->spreadsheetId
    );
    $res->Get($range) if $range;

    return $res;
}


=head2 GetCells($range) -> @cells|$cells

Obtain cells value by a range. 

Parameters:

=over

=item $range - cell range in A1 notation

=back

Returns:

Cell values nested array. ARRAY or ARRAYREF depending on context.
Structure: [[#row1], [#row2], ...]

See also:

https://developers.google.com/sheets/api/reference/rest/v4/spreadsheets.values/get

https://developers.google.com/sheets/api/guides/concepts#a1_notation

=cut

sub GetCells {
    my $self = shift;
    my $range = shift;

    my $vals_obj = $self->ValueRange($range);
    my $vals = $vals_obj->values;

    return wantarray ? @$vals : $vals;
}


=head2 SetCells($range, \@values) -> @cells_result|$cells_result

Write cells value to a given range

Parameters:

=over

=item $range - cell range in A1 notation

=item \@values - ARRAYREF with data. Structure: [[#row1], [#row2], ...]

=back

Returns:

Values nested array of the same cells returned by API after writing. 
ARRAY or ARRAYREF depending on context. Structure: [[#row1], [#row2], ...]

See also:

https://developers.google.com/sheets/api/reference/rest/v4/spreadsheets.values/update

https://developers.google.com/sheets/api/guides/concepts#a1_notation

=cut

sub SetCells {
    my $self = shift;
    my $range = shift;
    my $values = shift;

    my $range_obj = $self->ValueRange();
    $range_obj->range($range);
    $range_obj->values($values);

    $range_obj->Put(1);

    return wantarray ? @{$range_obj->values} : $range_obj->values;
}


=head2 GetCell($addr)

Obtain one cell value by an address

Parameters:

=over

=item $addr - one cell address in A1 notation. Range not accepted, for range use GetCells

=back

Returns:

Cell value or undef if cell is empty

=cut

sub GetCell {
    my $self = shift;
    my $addr = shift;

    unless ($self->_match_a1_cell($addr)) {
        die "[RT::Extension::GSuite]: Wrong cell address passed: $addr";
    }

    my @vals = $self->GetCells($addr);
    return @vals ? $vals[0][0] : (undef);
}


=head2 SetCell($addr, $value)

Write one cell value by an address

Parameters:

=over

=item addr - one cell address in A1 notation. Range not accepted, for range use SetCells

=item value - new value

=back

Returns:

Cell value returned by API after writing or undef if cell is empty

=cut

sub SetCell {
    my $self = shift;
    my $addr = shift;
    my $value = shift;

    unless ($self->_match_a1_cell($addr)) {
        die "[RT::Extension::GSuite]: Wrong cell address passed: $addr";
    }

    my @vals = $self->SetCells($addr, [[$value]]);
    return @vals ? $vals[0][0] : (undef);
}

sub _match_a1_cell {
    shift if ref $_[0];
    $_[0] =~ /^([^!]+!)?([A-Za-z]+[1-9][0-9]*)$/;
}

1;
