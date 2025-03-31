#!/usr/bin/perl

use Modern::Perl;

use CGI qw ( -utf8 );

use C4::Context;
use lib C4::Context->config("pluginsdir");

use Koha::Plugin::Aunpyz::EbookCheckout;

my $cgi = new CGI;

my $ebookcheckout = Koha::Plugin::Aunpyz::EbookCheckout->new({ cgi => $cgi });

my $cardnumber = $cgi->param("cardnumber") || '';
my $barcode = $cgi->param("barcode") || '';

$ebookcheckout->issuable( $cardnumber, $barcode );
