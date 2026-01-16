#!/usr/bin/perl

use Modern::Perl;

use CGI qw ( -utf8 );
use JSON;

use C4::Context;
use lib C4::Context->config("pluginsdir");

use Koha::Plugin::Aunpyz::EbookCheckout;

my $cgi = new CGI;

my $ebookcheckout = Koha::Plugin::Aunpyz::EbookCheckout->new({ cgi => $cgi });

my $barcode = $cgi->param('barcode');

my ( $error, $returned ) = $ebookcheckout->ebookcheckin($barcode);
if ( scalar keys %$error ) {
    print $cgi->header(
        {
            -status => 400,
            -type => 'application/json'
        });
    print to_json( $error );
} else {
    print $cgi->header(
        {
            -status => 204,
            -type => 'application/json'
        });
}
