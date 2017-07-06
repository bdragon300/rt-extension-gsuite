# Summary

RT::Extension::GSuite - Google GSuite services for the Request Tracker

# Description

The extension allows to work with Google GSuite products from Request Tracker
Scrips. Uses Google API v4 with JWT authorization (Google Service Account).

Work approach: create Scrip, that runs Action from this extension
(GoogleSheet for example) and write Template, which contains work logic. Set
config headers inside Template. When Template code executes, it's standart 
context complements by API object variables ($Sheet for example) through which
you can work with API or raw data if you want only read/write smth for example.

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
3. Download generated .json file, place it to secure place
4. Set its permissions to 400 and uid to rt user's uid
5. Add account to $GoogleServiceAccounts config option and specify file path

# Actions

## GoogleSheets

### Summary

This action is intended to work with Google Sheets spreadsheet. The passed 
template sets up parameters of work by headers. Also all interact logic places
into template code. 

You can work with spreadsheet in two ways: simple and complex. 

Simple: you specify cells by a header, e.g. "X-Read-Cells: A1:B4" and their 
values will be loaded to the ```$$Cells``` variable. Similarly you can specify 
another range, e.g. "X-Write-Cells: C4:C20", put values into ```$$Cells```
inside template code and spreadsheet will be updated by Action afterwards. 
(Always use this variable with $$ before name).

If you want implement more complex behavior, you can manipulate already 
preloaded spreadsheet object via $Sheet variable.

### Execute sequence

1. builds context contains JWT auth, request objects and initialized 
Spreadsheet object (headers from passed templates will be used for configuration). 
Authorization will be performed if necessary;
2. if X-Read-Cells template header is specified, then loads appropriate cell 
values from the spreadsheet and puts them to ```$$Cells``` template variable
3. performs template parsing process (RT parses and executes code inside)
4. if X-Write-Cells template header is specified, then writes ```$$Cells``` 
template variable data to appropriate cells in the spreadsheet

### Templates

#### Headers

* **X-Spreadsheet-Id** - Required. Google spreadsheet id. See: 
https://developers.google.com/sheets/api/guides/concepts#spreadsheet_id
* **X-Service-Account-Name** - Optional. Determine what account use. Default
is 'default'.
* **X-Read-Cells** - Optional. If set must contain cell range in A1 notation,
e.g. A1:B4. These cells will be read before template parse and their values will
be put into ```$$Cells``` variable inside template context. Default API options
will be used (majorDimension='ROWS'. i.e array of rows that contains cells).
* **X-Write-Cells** - Optional. If set must contain cell range in A1 notation,
e.g. A1:B4. These cells will be filled from ```$$Cells``` variable after 
template parse process finished and code evaluated. Default API options will be used.

#### Template context

* **```$$Cells```** - REF to ARRAYREF. Contains cells data preliminary read (if 
set, empty array otherwise) and data that will be written afterwards (if set, 
ignored otherwise)
* **```$Sheet```** - RT::Extension::GSuite::Spreadsheet object of current 
spreadsheet.

### Examples

#### Simple read

```
X-Spreadsheet-Id: a8fdc205a9f19cc1c7507a60c4f01b13d11d7fd0a
X-Read-Cells: A1:B1

{
    $Ticket->AddCustomFieldValue(Field=>12, Value=>$$Cells->[0]->[0]);
    $Ticket->AddCustomFieldValue(Field=>15, Value=>$$Cells->[0]->[1]);
}
```

#### Simple read/write

```
X-Spreadsheet-Id: a8fdc205a9f19cc1c7507a60c4f01b13d11d7fd0a
X-Read-Cells: A1
X-Write-Cells: Analytics!C3:D4

{
    $Ticket->AddCustomFieldValue(Field=>12, Value=>$$Cells->[0]->[0]);
    
    $$Cells = [["Debet", "Credit"], [100, 1000]]; #[[C3:C4], [D3:D4]];
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
    
    # Cells fills as same as previous example, but we changed
    #  majorDimension api parameter to 'COLUMNS'
    # See: https://developers.google.com/sheets/api/reference/rest/v4/spreadsheets.values/get

    my $data = [["Debet", 100], ["Credit", 1000]]; #[[C3:D3], [C4:D4]];
    $Sheet->SetCells("Analytics!C3:D4", $data, majorDimension=>'COLUMNS');
}
```
