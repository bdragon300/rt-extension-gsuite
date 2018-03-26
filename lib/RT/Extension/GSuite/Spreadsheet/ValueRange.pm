package RT::Extension::GSuite::Spreadsheet::ValueRange;

use 5.010;
use strict;
use warnings;
use Mouse;
use Mouse::Util::TypeConstraints;

=head1 NAME

  RT::Extension::GSuite::Spreadsheet::ValueRange - Cells range in a spreadsheet

  More: https://developers.google.com/sheets/api/reference/rest/v4/spreadsheets.values

=head1 AUTHOR

Igor Derkach, E<lt>gosha753951@gmail.comE<gt>

=cut

extends 'RT::Extension::GSuite::BaseObject';

with qw(RT::Extension::GSuite::Roles::Request);


subtype 'a1_notation'
    => as 'Str'
    => where { /^([^!]+!)?([A-Za-z]+\$?[1-9][0-9]*\$?:)?([A-Za-z]+\$?[1-9][0-9]*\$?)$/ }
    => message { "Cell/range address does not meet A1 notation: $_" };

subtype 'major_dimension_constraint'
    => as 'Str',
    => where { /^(ROWS|COLUMNS)$/ }
    => message { "Invalid majorDimension value: $_" };


=head1 ATTRIBUTES

=head2 majorDimension

How to interpret range values nested array: row to columns or vice versa.
Default is 'ROWS' means rows inside columns. Possible values: 'ROWS', 'COLUMNS'.

See also: https://developers.google.com/sheets/api/reference/rest/v4/spreadsheets.values

=cut

has majorDimension => (
    is => 'rw',
    isa => 'major_dimension_constraint',
    required => 1,
    default => 'ROWS',
);


=head2 range

Cells range in A1 notation.

See: https://developers.google.com/sheets/api/guides/concepts#a1_notation

=cut 

has range => (
    is => 'rw',
    isa => 'a1_notation'
);


=head2 values

Cells values nested array

=cut

has 'values' => (
    is => 'rw',
    isa => 'ArrayRef',
    auto_deref => 1,
    default => sub { [] }
);


=head2 spreadsheetId

=cut

has spreadsheetId => (
    is => 'rw',
    isa => 'Str',
    required => 1
);

=head2 request_params

Hashref with query parameters passed with GET requests

See: https://developers.google.com/sheets/api/reference/rest/v4/spreadsheets.values/get

=cut

has request_params => (
    is => 'rw',
    isa => 'HashRef',
    required => 1,
    auto_deref => 1,
    default => sub { {  # Coderef instead of hashref, see Mouse docs
        # https://developers.google.com/sheets/api/reference/rest/v4/spreadsheets.values/get
        # majorDimension => 'ROWS',
        # valueRenderOption => 'FORMATTED_VALUE',
        # dateTimeRenderOption => 'SERIAL_NUMBER',
    } }
);

has +suburl => (
    is => 'rw',
    default => '/spreadsheets/%s/values/%s'
);


=head1 METHODS

=head2 Get($range) -> boolean

Get object by range

Parameters:

=over

=item $range - cells range

=back

Returns:

Whether operation was successfull

=cut

sub Get {
    my $self = shift;
    my $range = shift;

    my $suburl = sprintf $self->suburl, $self->spreadsheetId, $range;
    my ($content, $res) = $self->_Request(GET => $suburl, $self->request_params);

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

    unless ($self->range) {
        die '[RT::Extension::GSuite]: Unable to reload ValueRange object ' .
            'with empty range';
    }

    $self->Get($self->range);
}


=head2 Save($reload_after, %API_ARGS => DEFAULTS) -> boolean

Write current object to a spreadsheet.

If $reload_after is 1 then API will be claimed to include the same range into
response after write (set includeValuesInResponse API flag). Also set 
$reload_after overrides includeValuesInResponse flag in %API_ARGS if any.

%API_ARGS allows to alter the API request. Omitted args contain their default 
values. See: https://developers.google.com/sheets/api/reference/rest/v4/spreadsheets.values/update

Parameters:

=over

=item $reload_after -- Required. Fill object with returned range after write

=item %API_ARGS -- Optional. Query parameters

=back

Returns:

Whether operation was successfull

=cut

sub Save {
    my $self = shift;
    my $reload_after = shift;
    my %api_args = (
        valueInputOption => 'USER_ENTERED',
        includeValuesInResponse => 0,
        responseValueRenderOption => 'FORMATTED_VALUE',
        responseDateTimeRenderOption => 'SERIAL_NUMBER',
        @_
    );

    my %body = map { $_ => $self->{$_} } qw(range majorDimension values);

    $api_args{includeValuesInResponse} = 1
        if ($reload_after);

    my $suburl = sprintf $self->suburl, $self->spreadsheetId, $self->range;
    my ($content, $res) = $self->_Request(
        PUT => $suburl, 
        \%api_args,
        \%body
    );

    return (undef) unless ($res->is_success);

    if ($reload_after) {
        if (ref $content->{updatedData} eq 'HASH') {
            $self->_FillAttributes(%{$content->{updatedData}}) if ($reload_after);
        } else {
            die '[RT::Extension::GSuite]: Unable to reload ValueRange with ' .
                'updatedData since request is successfull but nothing returned';
        }
    }

    return 1;
}


=head2 Row($number) -> @row|$row

Extract row with given number from 'values' and return it as one-dimentional 
array. Takes into account the 'majorDimentional' property.

$number counts from 1. Negative number returns approriate row from the end.
E.g. row with number -1 means the last one in range.

Parameters:

=over

=item $number -- Required. Row number counting from 1, or negative counting from -1

=back

Returns:

=over

=item Given row as ARRAY or ARRAYREF depending on context. 

=item undef if row with given number out of range

=back

=cut

sub Row {
    my $self = shift;
    my $number = shift // 0;

    return (undef) if ($number == 0);
    $number-- if ($number > 0);

    my @res;
    if ($self->majorDimension eq 'ROWS') {
        return (undef) unless exists $self->values->[$number];  # No such row
        @res = @{$self->values->[$number]};
    } elsif ($self->majorDimension eq 'COLUMNS') {
        return (undef)   # No such row
            unless (exists $self->values->[0] && exists $self->values->[0]->[$number]);
        @res = map { $_->[$number] } @{$self->values};
    }

    return wantarray ? @res : \@res;
}


=head2 Column($number) -> @column|$column

Extract column with given number from 'values' and return it as one-dimentional 
array. Takes into account the 'majorDimentional' property.

$number counts from 1. Negative number returns approriate column from the end.
E.g. column with number -1 means the last one in range.

Parameters:

=over

=item $number -- Required. Column number counting from 1, or negative counting from -1

=back

Returns:

=over

=item Given column as ARRAY or ARRAYREF depending on context. 

=item undef if column with given number out of range

=back

=cut

sub Column {
    my $self = shift;
    my $number = shift // 0;

    return (undef) if ($number == 0);
    $number-- if ($number > 0);

    my @res;
    if ($self->majorDimension eq 'ROWS') {
        return (undef)   # No such column
            unless (exists $self->values->[0] && exists $self->values->[0]->[$number]);
        @res = map { $_->[$number] } @{$self->values};
    } elsif ($self->majorDimension eq 'COLUMNS') {
        return (undef) unless exists $self->values->[$number];  # No such column
        @res = @{$self->values->[$number]};
    }

    return wantarray ? @res : \@res;
}


before qw(Save Row Column) => sub {
    my $self = shift;

    unless ($self->range) {
        die '[RT::Extension::GSuite]: Unable to operate ValueRange ' .
            'object with empty range';
    }
};

1;
