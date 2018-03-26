# RT::Action::GoogleSheets

## Summary

This action is a part of RT::Extension::GSuite and intended to work with 
Google Sheets spreadsheet. The specified template sets up parameters of action
in headers. The whole interact logic places into template code.You can work with automatically preloaded spreadsheet or load it youself in code. See examples below.

You can work with spreadsheet in two ways: simple and complex. 

### Simple way to work

Simple way can be used when you want just read and/or write one cell range.

Here the example:

```
X-Spreadsheet-Id: a8fdc205a9f19cc1c7507a60c4f01b13d11d7fd0a
X-Read-Cells: A1:B1
X-Write-Cells: Analytics!A1:B1

{
    $Ticket->AddCustomFieldValue(Field=>12, Value=>$$Cells->[0]->[0]); # A1
    $Ticket->AddCustomFieldValue(Field=>15, Value=>$$Cells->[0]->[1]); # B1
    $$Cells->[0]->[0] = 'Gotcha!';
}
```

What happens here: range mentioned in ```X-Read-Cells``` header automatically loads before template code get executed and become available via $$Cells variable. After code has executed the $$Cells contents automatically writes to the pointed range. That's all.

You can omit ```X-Read-Cells``` or ```X-Read-Cells``` and appropriate operation will not be performed. Header ```X-Spreadsheet-Id``` is required anyway.

### Complex way to work

Complex way allows to manipulate several spreadsheets and gives more control over cells.

The $Sheet variable is also available in template. This is RT::Extension::GSuite::Spreadsheet object, so see appropriate perldoc. 
Initially $Sheet contains empty object not bound to concrete spreadsheet. But if you specified ```X-Spreadsheet-Id``` header then $Sheet automatically loaded with that spreadsheet before template get executed.

Here the some of examples:

```
X-Spreadsheet-Id: a8fdc205a9f19cc1c7507a60c4f01b13d11d7fd0a

{
    $Ticket->AddCustomFieldValue(
        Field=>"A1 formula",
        Value=>$Sheet->GetCell("A1")
    );

    my $data = [["Debet", "Credit"], [100, 1000]];
    $Sheet->SetCells("Analytics!A1:B2", $data);
    # Was wrote:
    # -----------------------
    # |   |   A    |   B    |
    # -----------------------
    # | 1 | Debet  | Credit |
    # -----------------------
    # | 2 | 100    | 1000   |
    # -----------------------
}
```

```
{
    $Sheet->Get('a8fdc205a9f19cc1c7507a60c4f01b13d11d7fd0a');

    my $range1 = $Sheet->ValueRange('A1:B2');  # ValueRange object
    my @to_write = (  # 2x2
        ['=rand()', '=rand()'],  # First row with formulas
        [rand(100), rand(100)]   # Second row with numbers
    );
    $range1->values(\@to_write);  # Set 'values' property

    $range1->Save(1);  # Write data. 1 means reload object with new values (formulas will be calculated)

    $Ticket->Comment(Content => 'Formula results: ' . join(',', $range1->Row(1)));
    $Ticket->Comment(Content => 'Number results: ' . join(',', $range1->Row(2)));
}
```

```
{
    $Sheet->Get('a8fdc205a9f19cc1c7507a60c4f01b13d11d7fd0a');
    my $range2 = $Sheet->ValueRange;  # Empty ValueRange object

    # We need raw values
    # https://developers.google.com/sheets/api/reference/rest/v4/spreadsheets.values/get
    $range->request_params->{valueRenderOption} = 'FORMULA';  # FORMATTED_VALUE by default

    # Retrieve data from one of two sheets depending on day of month
    if (`date +%d` % 2) {
        $range2->Get('OddList!C1:D1');
    } else {
        $range2->Get('EvenList!C1:D1');
    }

    # Comment out current ticket with the first row values
    $Ticket->Comment(Content => 'Raw values from row #1: ' . join(',', $range2->Row(1)));
}
```

## Templates

### Headers

* **X-Spreadsheet-Id** - Optional. Google spreadsheet 
id. $Sheet variable will be bound with this spreadsheet. Required if you using ```X-Read-Cells``` or ```X-Read-Cells```
$Sheet->SetSpreadsheetId(id). How to retrieve spreadsheet: 
https://developers.google.com/sheets/api/guides/concepts#spreadsheet_id
* **X-Service-Account-Name** - Optional. What account name from extension
config to use to log in the Google account. Default is 'default'.
* **X-Read-Cells** - Optional. Cell range in A1 notation,
e.g. A1:B4. Put these values to $$Cells variable before template code get executed.
* **X-Write-Cells** - Optional. Cell range in A1 notation,
e.g. A1:B4. Retrieve values from $$Cells variable and write them to appropriate cells after template code get executed.

Note: the Action reads X-* headers value "as-is", so the code placed there  will not be executed.

### Variables

* **```$$Cells```** - REF to ARRAYREF. Contains cells data preliminary read 
(empty array if X-Read-Cells is not set) and data that will be written 
afterwards (ignores if X-Write-Cells is not set).
* **```$Sheet```** - RT::Extension::GSuite::Spreadsheet object of the current
spreadsheet.


# Author

Igor Derkach, <gosha753951@gmail.com>


# Bugs

Please report any bugs or feature requests to the author.


# Copyright and license

Copyright 2017 Igor Derkach, <https://github.com/bdragon300/>

This program is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.

Request Tracker (RT) is Copyright Best Practical Solutions, LLC.
