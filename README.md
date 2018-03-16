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

[RT::Action::GoogleSheets](README.GoogleSheets.md)

# Author

Igor Derkach, <gosha753951@gmail.com>


# Bugs

Please report any bugs or feature requests to the author.


# Copyright and license

Copyright 2017 Igor Derkach, <https://github.com/bdragon300/>

This program is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.

Request Tracker (RT) is Copyright Best Practical Solutions, LLC.
