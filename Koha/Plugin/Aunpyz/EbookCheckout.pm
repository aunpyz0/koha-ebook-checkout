package Koha::Plugin::Aunpyz::EbookCheckout;

use Modern::Perl;

use XML::Simple;
use UUID qw ( uuid );
use Try::Tiny;
use File::Path qw ( make_path remove_tree );
use IO::File;

use base qw( Koha::Plugins::Base );

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
use Koha::UploadedFiles;

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

## Table names
our $checkouts_table = 'checkouts';

## Upload path
our $upload_path = 'plugin_ebook_checkout';

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

    my $checkouts_table = $self->get_qualified_table_name($checkouts_table);
    my @installer_statements = (
        q { INSERT INTO marc_tag_structure (tagfield,liblibrarian,libopac,`repeatable`,mandatory,authorised_value,frameworkcode) VALUES 
         ('857','PRIVATE EBOOK URL','PRIVATE EBOOK URL',0,0,'','') ON DUPLICATE KEY UPDATE tagfield=tagfield,frameworkcode=frameworkcode; },
        q { INSERT INTO marc_subfield_structure (tagfield,tagsubfield,liblibrarian,libopac,`repeatable`,mandatory,kohafield,tab,authorised_value,authtypecode,value_builder,isurl,hidden,frameworkcode,seealso,link,defaultvalue,maxlength) VALUES
         ('857','u','Uniform Resource Identifier','Uniform Resource Identifier',0,0,'biblioitems.url',8,'','','upload.pl',1,4,'',NULL,'','',9999) ON DUPLICATE KEY UPDATE tagfield=tagfield; },
        q { INSERT INTO columns_settings (module,page,tablename,columnname,cannot_be_toggled,is_hidden) VALUES
         ('opac','biblio-detail','holdingst','item_barcode',0,0) ON DUPLICATE KEY UPDATE is_hidden=0, cannot_be_toggled=0; },
        q { INSERT INTO borrower_attribute_types (code,description,`repeatable`,unique_id,opac_display,opac_editable,staff_searchable,authorised_value_category,display_checkout,category_code,class) VALUES
         ('SHOW_BCODE','Show Barcode',0,0,0,0,0,'',0,NULL,'') ON DUPLICATE KEY UPDATE code=code; },
        qq { CREATE TABLE IF NOT EXISTS $checkouts_table (
            `uuid` varchar(36) NOT NULL,
            `filename` varchar(255) NOT NULL,
            `issue_id` int(11) NOT NULL,
            PRIMARY KEY (`uuid`),
            CONSTRAINT FOREIGN KEY (`issue_id`) REFERENCES issues (`issue_id`)
                ON DELETE CASCADE
         ) ENGINE = INNODB DEFAULT CHARSET=utf8 COLLATE=utf8_unicode_ci; },
    );
    for ( @installer_statements ) {
        my $sth = C4::Context->dbh->prepare( $_ );
        $sth->execute or die C4::Context->dbh->errstr;
    }

    make_path( $self->_dir() );

    my $opacuserjs = $self->_prepareopacuserjs();

    $opacuserjs .= q{{
/* JS for Koha Ebook Checkout Plugin */
$(document).ready(function() {
    const pathname = $(location).attr('pathname');
    if (pathname.endsWith('opac-detail.pl')) {
        $.ajax({
            type: 'GET',
            url: `/ebook-checkout/opac-detail.pl${$(location).attr('search').replace(/=(?=&|$)/gm, '')}`,
            cache: false,
            success: function(template) {
                $('body').append(template)
            },
        });
    } else if (pathname.endsWith('opac-user.pl')) {
        $.ajax({
            type: 'GET',
            url: '/ebook-checkout/opac-user.pl',
            cache: false,
            success: function(template) {
                $('body').append(template)
            },
        });
    }
});
/* End of JS for Koha Ebook Checkout Plugin */}};
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
    my $checkouts_table = $self->get_qualified_table_name($checkouts_table);
    my @uninstaller_statements = (
        q { DELETE FROM marc_tag_structure WHERE tagfield=857; },
        q { DELETE FROM marc_subfield_structure WHERE tagfield=857; },
        qq { DROP TABLE IF EXISTS $checkouts_table; },
    );
    for ( @uninstaller_statements ) {
        my $sth = C4::Context->dbh->prepare( $_ );
        $sth->execute or die C4::Context->dbh->errstr;
    }

    my $opacuserjs = $self->_prepareopacuserjs();
    C4::Context->set_preference( 'opacuserjs', $opacuserjs );

    remove_tree( $self->_dir() );

    return 1;
}

## The existance of a 'tool' subroutine means the plugin is capable
## of running a tool. The difference between a tool and a report is
## primarily semantic, but in general any plugin that modifies the
## Koha database should be considered a tool
sub tool {
    my ( $self, $args ) = @_;
}

sub _dir() {
    my ( $self ) = @_;

    return C4::Context->config('upload_path') . '/' . $upload_path;
}

sub _prepareopacuserjs() {
    my ( $self ) = @_;

    my $opacuserjs = C4::Context->preference( 'opacuserjs' );
    $opacuserjs =~ s/\/\* JS for Koha Ebook Checkout Plugin.*End of JS for Koha Ebook Checkout Plugin \*\///gs;

    return $opacuserjs;
}

sub _getsession {
    my ( $self ) = @_;
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
            return $session;
        }
    }
    return undef;
}

sub _getbiblionumber {
    my ( $self, $barcode) = @_;

    my $item = C4::Items::GetItem({ barcode => $barcode });
    return $item->{biblionumber};
}

sub _getprivateebook {
    my ( $self, $biblionumber ) = @_;

    my $xml = C4::Biblio::GetXmlBiblio( $biblionumber );
    $xml = XMLin($xml);
    my $datafield = $xml->{datafield};
    my ( $privateebook ) = grep { $_->{tag} eq 857 && $_->{subfield}->{code} eq 'u' } @$datafield;

    return $privateebook->{subfield}->{content};
}

sub _getprivateebookfilerecord {
    my ( $self, $biblionumber ) = @_;

    my $ebookurl = $self->_getprivateebook( $biblionumber ) || '';
    my $hash = ( split( /\?id=/, $ebookurl ) )[1];

    return Koha::UploadedFiles->search({
        hashvalue => $hash,
        public => 1,
    })->next;
}

sub hasprivateebook {
    my ( $self, $biblionumber ) = @_;

    return $self->_getprivateebook( $biblionumber ) ? 1 : 0;
}

sub opacdetail {
    my ( $self, $biblionumber ) = @_;
    my $cgi = $self->{cgi};

    my $session = $self->_getsession();
    my $template = $self->get_template({ file => 'opac-detail.tt' });
    $template->param(
        loggedin => $session ? 1 : 0,
    );

    $self->output_html( $template->output() );
}

sub opacuser {
    my ( $self ) = @_;
    my $cgi = $self->{cgi};

    my $session = $self->_getsession();
    my $template = $self->get_template({ file => 'opac-user.tt' });
    $template->param(
        loggedin => $session ? 1 : 0,
    );

    $self->output_html( $template->output() );
}

sub getlinks {
    my ( $self ) = @_;
    my $cgi = $self->{cgi};

    my $session = $self->_getsession();
    if ( $session ) {
        my $checkouts_table = $self->get_qualified_table_name($checkouts_table);
        my $checkouts = C4::Context->dbh->selectall_arrayref( qq|
            SELECT co.uuid, it.barcode FROM items it
            INNER JOIN issues iss ON iss.itemnumber=it.itemnumber
            INNER JOIN $checkouts_table co ON co.issue_id=iss.issue_id
            WHERE iss.borrowernumber=?;
        |, { Slice => {} }, $session->param("number") );
        return ( {}, $checkouts );
    }
    return ( { "UNAUTHORIZED" => 1 } );
}

sub ebookcheckout {
    my ( $self, $barcode ) = @_;
    my $cgi = $self->{cgi};

    my $session = $self->_getsession();
    if ( $session ) {
        my $biblionumber = $self->_getbiblionumber( $barcode );
        if ( $biblionumber ) {
            if ( $self->hasprivateebook( $biblionumber ) ) {
                my $borrower;
                my $cardnumber = $session->param("cardnumber");
                if ( $cardnumber ) {
                    $borrower = Koha::Patrons->find( { cardnumber => $cardnumber } );
                    $borrower = $borrower->unblessed if $borrower;
                }

                my ( $impossible, $needconfirm ) = CanBookBeIssued(
                    $borrower,
                    $barcode,
                    undef,
                    0,
                    C4::Context->preference("AllowItemsOnHoldCheckoutSCO")
                );

                # my $confirm_required = 0;
                # my $issue_error;
                # if ( $confirm_required = scalar keys %$needconfirm ) {
                #     for my $error ( qw( UNKNOWN_BARCODE max_loans_allowed ISSUED_TO_ANOTHER NO_MORE_RENEWALS NOT_FOR_LOAN DEBT WTHDRAWN RESTRICTED RESERVED ITEMNOTSAMEBRANCH EXPIRED DEBARRED CARD_LOST GNA INVALID_DATE UNKNOWN_BARCODE TOO_MANY DEBT_GUARANTEES USERBLOCKEDOVERDUE PATRON_CANT PREVISSUE NOT_FOR_LOAN_FORCING ITEM_LOST) ) {
                #         if ( $needconfirm->{$error} ) {
                #             $issue_error = $error;
                #             last;
                #         }
                #     }
                # }
                if ( scalar keys %$impossible || scalar keys %$needconfirm ) {
                    return ( $impossible, $needconfirm );
                }

                # if (scalar keys %$impossible) {
                #     my $issue_error = (keys %$impossible)[0]; # FIXME This is wrong, we assume only one error and keys are not ordered

                #     warn "issue_error: $issue_error";

                #     # TODO: do something
                # } elsif ( $needconfirm->{RENEW_ISSUE} ) {
                #     # TODO: might have to handle renewal
                # } else {
                    my ( $hold_existed, $item );
                    if ( C4::Context->preference('HoldFeeMode') eq 'any_time_is_collected' ) {
                        # There is no easy way to know if the patron has been charged for this item.
                        # So we check if a hold existed for this item before the check in
                        $item = Koha::Items->find({ barcode => $barcode });
                        $hold_existed = Koha::Holds->search(
                            {
                                -and => {
                                    borrowernumber => $borrower->{borrowernumber},
                                    -or            => {
                                        biblionumber => $item->biblionumber,
                                        itemnumber   => $item->itemnumber
                                    }
                                }
                            }
                        )->count;
                    }
                    my $dbh = C4::Context->dbh;
                    $dbh->{AutoCommit} = 0;
                    my $uuid = uuid();
                    ( $impossible, my %checkout ) = try {
                        my $issue = AddIssue( $borrower, $barcode );
                        my $ebookfilerecord = $self->_getprivateebookfilerecord( $biblionumber );
                        # TODO: encrypt file
                        my $fh = $ebookfilerecord->file_handle if $ebookfilerecord or die { "OPEN_FILE_FAILED" => 1 };
                        my $encryptfh = IO::File->new( $self->_dir() . "/$uuid", "w" ) or die { "CREATE_FILE_FAILED" => 1 };
                        $encryptfh->binmode;
                        while (read($fh, my $block, 16)) {
                            print $encryptfh $block;
                        }
                        $encryptfh->close();

                        my $checkouts_table = $self->get_qualified_table_name($checkouts_table);
                        $dbh->do( qq|INSERT INTO $checkouts_table (uuid, filename, issue_id) VALUES (?, ?, ?)|, undef, $uuid, $ebookfilerecord->filename, $issue->issue_id ) or die { "INSERT_CHECKOUT_FAILED" => $dbh->errstr };
                        $dbh->commit;
                        $dbh->{AutoCommit} = 1;

                        if ( $hold_existed ) {
                            # my $dtf = Koha::Database->new->schema->storage->datetime_parser;
                            # $template->param(
                            #     # If the hold existed before the check in, let's confirm that the charge line exists
                            #     # Note that this should not be needed but since we do not have proper exception handling here we do it this way
                            #     patron_has_hold_fee => Koha::Account::Lines->search(
                            #         {
                            #             borrowernumber => $borrower->{borrowernumber},
                            #             accounttype    => 'Res',
                            #             description    => 'Reserve Charge - ' . $item->biblio->title,
                            #             date           => $dtf->format_date(dt_from_string)
                            #         }
                            #       )->count,
                            # );
                        }

                        return ( {}, ( "uuid" => $uuid ) );
                    } catch {
                        $dbh->rollback;
                        $dbh->{AutoCommit} = 1;
                        unlink $self->_dir() . "/$uuid";
                        # TODO: return meaningful error
                        return ( $_ );
                    };
                    return ( $impossible, $needconfirm, %checkout );
                # }
            }
            return ( { "NO_PRIVATE_EBOOK" => 1 } );
        }
        return ( { "UNKNOWN_BARCODE" => 1 } );
    }
    return ( { "UNAUTHORIZED" => 1 } );
}

sub getebookfilehandle {
    my ( $self, $uuid ) = @_;
    my $cgi = $self->{cgi};

    my $session = $self->_getsession();
    if ( $session ) {
        my ( $error, $fh ) = try {
            my $checkouts_table = $self->get_qualified_table_name($checkouts_table);
            my $checkout = C4::Context->dbh->selectrow_hashref( qq|SELECT uuid FROM $checkouts_table WHERE uuid=?|, undef, $uuid ) or die ( { "CHECKOUT_NOT_FOUND" => 1 } );
            my $fh = IO::File->new( $self->_dir() . "/$uuid", "r" ) or die ( { "OPEN_FILE_FAILED" => $! } );
            $fh->binmode;
            return ( {}, $fh );
        } catch {
            return ( $_ );
        };
        return ( $error, $fh );
    }
    return ( { "UNAUTHORIZED" => 1 } );
}

1;