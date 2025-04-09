package Koha::Plugin::Aunpyz::EbookCheckout;

use Modern::Perl;

use base qw(Koha::Plugins::Base);

use C4::Auth;
use C4::Context;
use C4::Koha;
use C4::Circulation;
use C4::Reserves;
use C4::Output;
use C4::Members;
use C4::Biblio;
use C4::Items;
use Koha::DateUtils qw( dt_from_string );
use Koha::Acquisition::Currencies;
use Koha::Patrons;
use Koha::Patron::Images;
use Koha::Patron::Messages;
use Koha::Token;

## Here we set our plugin version
our $VERSION = '0.0.1';

## Here is our metadata, some keys are required, some are optional
our $metadata = {
    name            => 'Ebook Checkout',
    author          => 'Aunnop Kattiyanet',
    date_authored   => '2025-03-26',
    date_updated    => '2025-03-26',
    minimum_version => '17.11',
    maximum_version => undef,
    version         => $VERSION,
    description     => 'This plugin adds the ability to checkout book with licensed ebook (857$u) via OPAC',
};


## This is the minimum code required for a plugin's 'new' method
## More can be added, but none should be removed
sub new {
    my ( $class, $args ) = @_;

    $args->{'metadata'} = $metadata;
    $args->{'metadata'}->{'class'} = $class;

    my $self = $class->SUPER::new($args);

    return $self;
}

## This is the 'install' method. Any database tables or other setup that should
## be done when the plugin if first installed should be executed in this method.
## The installation method should always return true if the installation succeeded
## or false if it failed.
sub install() {
    my ( $self, $args ) = @_;

    # TODO: customize marc_tag_structure to have tag 857
    # TODO: customize marc_subfield_structure to have tagsubfield u for tagfield 857

    my $opacuserjs = $self->_prepareopacuserjs();

    $opacuserjs .= q|
/* JS for Koha Ebook Checkout Plugin */
$(document).ready(function() {
    if ($(location).attr("pathname").endsWith("opac-detail.pl")) {
    }
});
/* End of JS for Koha Ebook Checkout Plugin */|;
    C4::Context->set_preference( 'opacuserjs', $opacuserjs );

    return 1;
}

## This is the 'upgrade' method. It will be triggered when a newer version of a
## plugin is installed over an existing older version of a plugin
sub upgrade {
    my ( $self, $args ) = @_;

    return 1;
}

## This method will be run just before the plugin files are deleted
## when a plugin is uninstalled. It is good practice to clean up
## after ourselves!
sub uninstall() {
    my ( $self, $args ) = @_;

    # TODO: remove all tagfield 857 from marc_subfield_structure
    # TODO: remove tag 857 from marc_tag_structure

    my $opacuserjs = $self->_prepareopacuserjs();
    C4::Context->set_preference( 'opacuserjs', $opacuserjs );

    return 1;
}

## The existance of a 'tool' subroutine means the plugin is capable
## of running a tool. The difference between a tool and a report is
## primarily semantic, but in general any plugin that modifies the
## Koha database should be considered a tool
sub tool {
    my ( $self, $args ) = @_;
}

sub _prepareopacuserjs() {
    my ( $self ) = @_;

    my $opacuserjs = C4::Context->preference( 'opacuserjs' );
    $opacuserjs =~ s/\/\* JS for Koha Ebook Checkout Plugin.*End of JS for Koha Ebook Checkout Plugin \*\///gs;

    return $opacuserjs;
}

sub issuable {
    my ( $self, $barcode ) = @_;
    my $cgi = $self->{cgi};

    my $sessionID = $cgi->cookie("CGISESSID");
    if ( $sessionID ) {
        my $session = C4::Auth::get_session($sessionID);
        # TODO: Check if session is expired?
        if ( $session && $session->param("id") ) {
            # TODO: Will this pop out of context?
            C4::Context->_new_userenv($sessionID);
            C4::Context->set_userenv(
                $session->param("number"),
                $session->param("id"),
                $session->param("cardnumber"),
                $session->param("firstname"),
                $session->param("surname"),
                $session->param("branch"),
                $session->param("branchname"),
                $session->param("flags"),
                $session->param("emailaddress"),
                $session->param("branchprinter"),
                $session->param("shibboleth")
            );

            my $borrower;
            my $cardnumber = $session->param("cardnumber");
            if ( $cardnumber ) {
                $borrower = Koha::Patrons->find( { cardnumber => $cardnumber } );
                $borrower = $borrower->unblessed if $borrower;
            }

            return CanBookBeIssued(
                $borrower,
                $barcode,
                undef,
                0,
                C4::Context->preference("AllowItemsOnHoldCheckoutSCO")
            );
        }
    }
    return ( { "UNAUTHORIZED" => 1 } );
}

1;