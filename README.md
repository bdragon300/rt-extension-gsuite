# Summary

RT::Extension::GSuite - Google GSuite services with JSON Web Token authorization

# Description

The extension allows to work with Google GSuite products from Request Tracker.
It uses Google API v4 with OAuth2 JWT authorization (Google Service Account).

Work approach: create a Scrip or a crontab task, that runs an Action
(GoogleSheet for example) and write Template that contains work logic. Set
config headers inside Template. And then work with Google services straight 
from template code via object interface.

See appropriate modules docs.

The extension supports many service accounts with their json files. Authorization
uses JSON Web Token when Google doesn't confirm user to access requested
priviledges. Google recommends this method for Server-to-Server communication
without user participation. [More](https://developers.google.com/identity/protocols/OAuth2)

# Installation

Dependencies:

* RT >= 4.2.0
* Furl >= 3.07
* Data::Validator >= 1.07
* Mojo::Collection
* Mojo::JWT::Google
* JSON >= 2.90
* Sub::Retry >= 0.06

Commands to install:

  perl Makefile.PL

  make
  
  make install

If you install this extension for the first time, you must to add needed objects
to the database:

  make initdb

Be careful, run the last command one time only, otherwise you can get duplicates
in the database.

# Configuration

RT_SiteConfig.pm configuration options.

## $GoogleServiceAccounts

```
Set($GoogleServiceAccounts, {'default'=>{...}, ...});
```

Required. This option sets available service account that will be used to access
Google API. Must contain at least one account with name 'default'. 

Example:

```
Set($GoogleServiceAccounts, {
  'default' => {
    json_file => '/etc/google_accounts/jsons/Default-1934acf34cc.json'
  },
  'outsourcing' => {
    json_file => '/etc/google_accounts/jsons/Outsourcing-55ccd98e302.json'
  }
});
```

## $InsecureJsonFile

```
Set($InsecureJsonFile, 1);
```

Optional. Set it to 1 to skip check key json file permissions. Default is 0.

# Usage

You can use the action in Scrips or via rt-crontool.

# Creating Google Service Account

Follow this link: https://developers.google.com/identity/protocols/OAuth2ServiceAccount#creatinganaccount

In few words:

1. Go to Google API manager, create project if needed
2. Create new Service Account
3. Download generated .json file, place it to the secure place
4. Set its permissions to 400 and uid to rt user's uid
5. Add an account to the $GoogleServiceAccounts config option and specify file path

# Actions

## GoogleSheets

### Summary

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

### Execute sequence

1. build context contained initialized objects: JWT auth, Request, 
Spreadsheet. (headers from given templates will be used for configuration). 
Authorization will be performed if necessary;
2. if X-Read-Cells template header is specified, then load appropriate 
cell values from the spreadsheet and put result to the $$Cells variable
3. perform standard template parsing process
4. if X-Write-Cells template header is specified, then write the $$Cells
data to the appropriate cells in the spreadsheet

### Templates

#### Headers

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

#### Template context

* **```$$Cells```** - REF to ARRAYREF. Contains cells data preliminary read 
(empty array if X-Read-Cells is not set) and data that will be written 
afterwards (ignores if X-Write-Cells is not set).
* **```$Sheet```** - RT::Extension::GSuite::Spreadsheet object of the current
spreadsheet.

### Examples

#### Simple read

```
X-Spreadsheet-Id: a8fdc205a9f19cc1c7507a60c4f01b13d11d7fd0a
X-Read-Cells: A1:B1

{
    $Ticket->AddCustomFieldValue(Field=>12, Value=>$$Cells->[0]->[0]); # A1
    $Ticket->AddCustomFieldValue(Field=>15, Value=>$$Cells->[0]->[1]); # B1
}
```

#### Simple read/write

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

#### Use $Sheet

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

# Author

Igor Derkach, <gosha753951@gmail.com>


# Bugs

Please report any bugs or feature requests to the author.


# Copyright and license

Copyright 2017 Igor Derkach, <https://github.com/bdragon300/>

This program is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.

Request Tracker (RT) is Copyright Best Practical Solutions, LLC.
