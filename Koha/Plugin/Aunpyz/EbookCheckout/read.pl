#!/usr/bin/perl

use Modern::Perl;

use CGI qw ( -utf8 );
use JSON;

use C4::Context;
use lib C4::Context->config("pluginsdir");

use Koha::Plugin::Aunpyz::EbookCheckout;

my $cgi = new CGI;

my $ebookcheckout = Koha::Plugin::Aunpyz::EbookCheckout->new({ cgi => $cgi });

my $uuid = $cgi->param("uuid") || '';
my ( $error, $ebookfh ) = $ebookcheckout->getebookfilehandle( $uuid );

if ( scalar keys %$error ) {
	if ( $error->{UNAUTHORIZED} ) {
		print $cgi->header(
			{
				-status => 401
			});
	} else {
		print $cgi->header(
			{
				-status => 400,
				-type => "application/json",
			});
		print to_json( $error );
	}
} else {
	print $cgi->header(
		{
			-status => 200,
			-type => "application/pdf",
		});
    while( <$ebookfh> ) {
        print $_;
    }
    $ebookfh->close;	
}
