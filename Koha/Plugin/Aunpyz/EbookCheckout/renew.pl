#!/usr/bin/perl

use Modern::Perl;

use CGI qw ( -utf8 );
use JSON;

use C4::Context;
use lib C4::Context->config("pluginsdir");

use Koha::Plugin::Aunpyz::EbookCheckout;

my $cgi = new CGI;

my $ebookcheckout = Koha::Plugin::Aunpyz::EbookCheckout->new({ cgi => $cgi });

my $uuid = $cgi->param('uuid');
my $method = $cgi->request_method();

if ( $method eq 'GET' ) {
    my ( $error, $renewable ) = $ebookcheckout->renewable($uuid);
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
                -status => 200,
                -type => 'application/json'
            });
        print to_json( { "RENEWABLE" => $renewable } );
    }
} elsif ( $method eq 'PUT' ) {
    my ( $error, $new_date_due, $renewable ) = $ebookcheckout->renew($uuid);
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
                -status => 200,
                -type => 'application/json'
            });
        print to_json( { "DATE_DUE" => $new_date_due->epoch, "RENEWABLE" => $renewable } );
    }
} else {
    print $cgi->header(
        {
            -status => 400,
            -type => 'application/json'
        });
    print to_json( { "METHOD_NOT_ALLOWED" => 1 } );
}
