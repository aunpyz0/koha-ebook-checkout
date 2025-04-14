#!/usr/bin/perl

use Modern::Perl;

use CGI qw ( -utf8 );
use JSON;

use C4::Context;
use lib C4::Context->config("pluginsdir");

use Koha::Plugin::Aunpyz::EbookCheckout;

my $cgi = new CGI;

my $ebookcheckout = Koha::Plugin::Aunpyz::EbookCheckout->new({ cgi => $cgi });

my $barcode = $cgi->param("barcode") || '';

my ( $impossible, $needconfirm, %checkout ) = $ebookcheckout->ebookcheckout( $barcode );

if ( scalar keys %$impossible || scalar keys %$needconfirm ) {
	if ( $impossible->{UNAUTHORIZED} ) {
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
	    # for my $error ( qw( UNKNOWN_BARCODE NO_PRIVATE_EBOOK ) ) {
	    #     if ( $impossible->{$error} ) {
		# 		print $cgi->header(
		# 			{
		# 				-status => 400
		# 			});
		# 		# TODO: print json body
	    #         exit 0;
	    #     }
	    # }
		my %json = ( 'impossible' => $impossible, 'needconfirm' => $needconfirm );
		my $json = encode_json \%json;
		print $json;
	}
} else {
	print $cgi->header(
		{
			-status => 200,
			-type => "application/json",
		});
	my $json = encode_json \%checkout;
	print $json;
}
