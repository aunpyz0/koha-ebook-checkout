# Required Perl Modules

- Crypt::CBC
- Crypt::Cipher::AES

## Installation

```bash
cpan Crypt::CBC Crypt::Cipher::AES
```

# Installing

The plugin system needs to be turned on by a system administrator.

To set up the Koha plugin system you must first make some changes to your install.

* Change `<enable_plugins>0<enable_plugins>` to `<enable_plugins>1</enable_plugins>` in your koha-conf.xml file
* Confirm that the path to `<pluginsdir>` exists, is correct, and is writable by the web server
* Change `<plugins_restricted>1</plugins_restricted>` to `<plugins_restricted>0</plugins_restricted>` in your koha-conf.xml file if you want non-admin account to install plugins
* Restart your webserver

Once plugin is installed an additional step is required
* Update apache config to alias perl script
```
   ScriptAlias /ebook-checkout "/var/lib/koha/{LIBRARY_NAME}/plugins/Koha/Plugin/Aunpyz/EbookCheckout"

   <Directory /var/lib/koha/{LIBRARY_NAME}/plugins/Koha/Plugin/Aunpyz/EbookCheckout>
      Options Indexes FollowSymLinks
      AllowOverride None
      Require all granted
   </Directory>
```