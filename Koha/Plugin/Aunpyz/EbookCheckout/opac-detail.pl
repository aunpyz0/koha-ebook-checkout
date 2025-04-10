#!/usr/bin/perl

use Modern::Perl;

use CGI qw ( -utf8 );
use XML::Simple;

use C4::Biblio;
use lib C4::Context->config("pluginsdir");

use Koha::Plugin::Aunpyz::EbookCheckout;

my $cgi = new CGI;

my $biblionumber = $cgi->param("biblionumber") || '';
if ( $biblionumber ) {
	my $xml = C4::Biblio::GetXmlBiblio( $biblionumber );
	$xml = XMLin($xml);
	my $datafield = $xml->{datafield};
	my ( $privateebook ) = grep { $_->{tag} eq 857 && $_->{subfield}->{code} eq 'u' } @$datafield;

	if ( $privateebook ) {
		my $ebookcheckout = Koha::Plugin::Aunpyz::EbookCheckout->new({ cgi => $cgi });
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