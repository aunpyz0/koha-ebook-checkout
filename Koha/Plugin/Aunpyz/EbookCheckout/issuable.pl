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

my ( $impossible, $needconfirm ) = $ebookcheckout->issuable( $barcode );

if ( $impossible->{UNAUTHORIZED} ) {
	print $cgi->header(
		{
			-status => 401
		});
}
else {
	# TODO: need to process into Either<ISSUABLE, NONISSUABLE>
	print $cgi->header(
		{
			-status => 200,
			-type => "application/json",
			-charset => "UTF-8",
			-encoding => "UTF-8"
		});

	my %json = ( 'impossible' => $impossible, 'needconfirm' => $needconfirm );
	my $json = encode_json \%json;
	print $json;
}
