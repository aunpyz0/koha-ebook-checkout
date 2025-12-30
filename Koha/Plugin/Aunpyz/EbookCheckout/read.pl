#!/usr/bin/perl

use Modern::Perl;

use CGI qw ( -utf8 );
use JSON;
use Crypt::CBC;
use Digest::SHA qw(sha256);

use C4::Context;
use lib C4::Context->config("pluginsdir");

use Koha::Plugin::Aunpyz::EbookCheckout;

my $cgi = new CGI;

my $ebookcheckout = Koha::Plugin::Aunpyz::EbookCheckout->new({ cgi => $cgi });

my $uuid = $cgi->param("uuid");
my $access_token = $cgi->http('X-Access');

my ( $error, $ebookfh ) = $ebookcheckout->getebookfilehandle( $uuid, $access_token );

if ( scalar keys %$error ) {
	print $cgi->header(
		{
			-status => 400,
			-type => "application/json",
		});
	print to_json( $error );
} else {
	print $cgi->header(
		{
			-status => 200,
			-type => "application/octet-stream",
		});
	my $password = 'P@ssw0rd';
	my $key = sha256($password);
	my $iv = Crypt::CBC->random_bytes(16);
	my $cipher = Crypt::CBC->new(
		{
			cipher      => 'Cipher::AES',
			key         => $key,
			iv          => $iv,
			pbkdf		=> 'none',
			header      => 'none',
			keysize     => 32,
			padding     => 'standard'
		}
	);

	print $iv;
	$cipher->start('encrypting');
	my $buffer;
	while ( read($ebookfh, $buffer, 4096) ) {
	    print $cipher->crypt($buffer);
	}
    print $cipher->finish();
    $ebookfh->close;	
}
