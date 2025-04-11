#!/usr/bin/perl

use Modern::Perl;

use CGI qw ( -utf8 );

use C4::Context;
use lib C4::Context->config("pluginsdir");

use Koha::Plugin::Aunpyz::EbookCheckout;

my $cgi = new CGI;

my $biblionumber = $cgi->param("biblionumber") || '';
if ( $biblionumber ) {
	my $ebookcheckout = Koha::Plugin::Aunpyz::EbookCheckout->new({ cgi => $cgi });
	
	if ( $ebookcheckout->hasprivateebook( $biblionumber ) ) {
		$ebookcheckout->opacdetail( $biblionumber );
		exit 0;
	}
}

print $cgi->header(
	{
		-status => 200,
		-type => "text/html",
		-charset => "UTF-8",
		-encoding => "UTF-8"
	});