# GoogleSheets

## Summary

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

## Execute sequence

1. build context contained initialized objects: JWT auth, Request, 
Spreadsheet. (headers from given templates will be used for configuration). 
Authorization will be performed if necessary;
2. if X-Read-Cells template header is specified, then load appropriate 
cell values from the spreadsheet and put result to the $$Cells variable
3. perform standard template parsing process
4. if X-Write-Cells template header is specified, then write the $$Cells
data to the appropriate cells in the spreadsheet

## Templates

### Headers

* **X-Spreadsheet-Id** - Optional, but usually set. Google spreadsheet 
id. If not set then you have to load spreadsheet manually using 
$Sheet->SetSpreadsheetId(id). Also you can't use another headers such 
X-Read-Cells in that case. Such behavior is suitable when spreadsheet id 
calculates during template code execution. See: 
https://developers.google.com/sheets/api/guides/concepts#spreadsheet_id
* **X-Service-Account-Name** - Optional. What account name from extension
config to use to log in the Google account. Default is 'default'.
* **X-Read-Cells** - Optional. Must contain cell range in A1 notation,
e.g. A1:B4. Values of these cells will be read before the template 
parsing and put into $$Cells variable inside template context. Default API 
options will be used (for instance, majorDimension='ROWS').
* **X-Write-Cells** - Optional. Must contain cell range in A1 notation,
e.g. A1:B4. These cells will be filled out from $$Cells variable content 
just after the template parse process has finished and the code has evaluated.
Default API options will be used.

Note: the Action obtains X-* headers value "as-is", before the some code 
executes. Use $Sheet variable inside the template code if you want more complex
behavior.

### Template context

* **```$$Cells```** - REF to ARRAYREF. Contains cells data preliminary read 
(empty array if X-Read-Cells is not set) and data that will be written 
afterwards (ignores if X-Write-Cells is not set).
* **```$Sheet```** - RT::Extension::GSuite::Spreadsheet object of the current
spreadsheet.

## Examples

### Simple read

```
X-Spreadsheet-Id: a8fdc205a9f19cc1c7507a60c4f01b13d11d7fd0a
X-Read-Cells: A1:B1

{
    $Ticket->AddCustomFieldValue(Field=>12, Value=>$$Cells->[0]->[0]); # A1
    $Ticket->AddCustomFieldValue(Field=>15, Value=>$$Cells->[0]->[1]); # B1
}
```

### Simple read/write

```
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
```

### Use $Sheet

```
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
```
