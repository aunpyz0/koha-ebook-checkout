package Koha::Plugin::Aunpyz::EbookCheckout;

use Modern::Perl;

use DateTime;
use XML::Simple;
use UUID qw ( uuid );
use Try::Tiny;
use File::Path qw ( make_path remove_tree );
use IO::File;

use base qw( Koha::Plugins::Base );

use C4::Auth;
use C4::Context;
use C4::Koha;
use C4::Circulation
  qw( CanBookBeIssued CanBookBeRenewed AddIssue AddReturn AddRenewal);
use C4::Reserves;
use C4::Output;
use C4::Members;
use C4::Biblio;
use Koha::Database;
use Koha::Items;
use Koha::DateUtils qw( dt_from_string );
use Koha::Acquisition::Currencies;
use Koha::Patrons;
use Koha::Patron::Images;
use Koha::Patron::Messages;
use Koha::Token;
use Koha::UploadedFiles;
use Koha::Checkouts;

## Here we set our plugin version
our $VERSION = '2.0.0';

## Here is our metadata, some keys are required, some are optional
our $metadata = {
    name            => 'Ebook Checkout',
    author          => 'Aunnop Kattiyanet',
    date_authored   => '2025-03-26',
    date_updated    => '2025-03-26',
    minimum_version => '25.11',
    maximum_version => undef,
    version         => $VERSION,
    description     =>
'This plugin adds the ability to checkout book with encryption upon request (857$u) via OPAC',
};

## Table names
our $checkouts_table = 'checkouts';
our $config_table    = 'config';

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
    my $config_table    = $self->get_qualified_table_name($config_table);
    my $hostname        = C4::Context->preference('OPACBaseURL');
    my $quoted_hostname = C4::Context->dbh->quote($hostname);

    my $encryption_key = join( '',
        map { ( 'a' .. 'z', 'A' .. 'Z', '0' .. '9' )[ rand 62 ] } 1 .. 8 );
    my $quoted_encryption_key = C4::Context->dbh->quote($encryption_key);

    my @installer_statements = (
q { INSERT INTO marc_tag_structure (tagfield,liblibrarian,libopac,`repeatable`,mandatory,authorised_value,frameworkcode) VALUES 
         ('857','PRIVATE EBOOK URL','PRIVATE EBOOK URL',0,0,'','') ON DUPLICATE KEY UPDATE tagfield=tagfield,frameworkcode=frameworkcode; },
q { INSERT INTO marc_subfield_structure (tagfield, tagsubfield, liblibrarian, libopac, `repeatable`, mandatory, important, kohafield, tab, authorised_value, authtypecode, value_builder, isurl, hidden, frameworkcode, seealso, link, defaultvalue, maxlength, display_order) VALUES
         ('857', 'u', 'Uniform Resource Identifier', 'Uniform Resource Identifier', 0, 0, 0, 'biblioitems.url', 8, '', '', 'upload.pl', 1, 4, '', NULL, '', '', 9999, 0) ON DUPLICATE KEY UPDATE tagfield=tagfield; },
q { INSERT INTO columns_settings (module,page,tablename,columnname,cannot_be_toggled,is_hidden) VALUES
         ('opac','biblio-detail','holdingst','item_barcode',0,0) ON DUPLICATE KEY UPDATE is_hidden=0, cannot_be_toggled=0; },
q { INSERT INTO borrower_attribute_types (code,description,`repeatable`,unique_id,opac_display,opac_editable,staff_searchable,authorised_value_category,display_checkout,category_code,class) VALUES
         ('SHOW_BCODE','Show Barcode',0,0,0,0,0,'',0,NULL,'') ON DUPLICATE KEY UPDATE code=code; },
        qq { CREATE TABLE IF NOT EXISTS $checkouts_table (
            `uuid` varchar(36) NOT NULL,
            `file_hashvalue` varchar(255) NOT NULL,
            `issue_id` int(11) NOT NULL,
            `access_code` varchar(6) NOT NULL,
            `access_token` text NULL,
            PRIMARY KEY (`uuid`),
            CONSTRAINT FOREIGN KEY (`issue_id`) REFERENCES issues (`issue_id`)
                ON DELETE CASCADE
         ) ENGINE = INNODB DEFAULT CHARSET=utf8 COLLATE=utf8_unicode_ci; },
        qq { CREATE TABLE IF NOT EXISTS $config_table (
            `name` varchar(255) NOT NULL,
            `value` text,
            PRIMARY KEY (`name`)
        ) ENGINE = INNODB DEFAULT CHARSET=utf8 COLLATE=utf8_unicode_ci; },
        qq { INSERT INTO $config_table (name, value) VALUES
         ('HOST_NAME', $quoted_hostname),
         ('ITEM_INTERVAL_DAY', '1'),
         ('ENCRYPTION_KEY', $quoted_encryption_key) },
    );
    for (@installer_statements) {
        my $sth = C4::Context->dbh->prepare($_);
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
    my $config_table    = $self->get_qualified_table_name($config_table);
    my @uninstaller_statements = (
        q { DELETE FROM marc_tag_structure WHERE tagfield=857; },
        q { DELETE FROM marc_subfield_structure WHERE tagfield=857; },
        qq { DROP TABLE IF EXISTS $checkouts_table; },
        qq { DROP TABLE IF EXISTS $config_table; },
    );
    for (@uninstaller_statements) {
        my $sth = C4::Context->dbh->prepare($_);
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
    my $cgi = $self->{cgi};

    unless ( $cgi->request_method() eq 'POST' ) {
        $self->_tool_step1();
    }
    else {
        $self->_tool_step2();
    }
}

sub _tool_step1 {
    my ( $self, $args ) = @_;

    my $config_table = $self->get_qualified_table_name($config_table);
    my $hostname     = C4::Context->dbh->selectrow_hashref(
        qq| SELECT value FROM $config_table WHERE name = 'HOST_NAME' |)
      or die "Could not find HOST_NAME in config table";
    my $interval_day = C4::Context->dbh->selectrow_hashref(
        qq| SELECT value FROM $config_table WHERE name = 'ITEM_INTERVAL_DAY' |)
      or die "Could not find ITEM_INTERVAL_DAY in config table";
    my $encryption_key = C4::Context->dbh->selectrow_hashref(
        qq| SELECT value FROM $config_table WHERE name = 'ENCRYPTION_KEY' |)
      or die "Could not find ENCRYPTION_KEY in config table";
    my $template = $self->get_template( { file => 'tool.tt' } );
    $template->param(
        hostname       => $hostname->{value},
        interval_day   => $interval_day->{value},
        encryption_key => $encryption_key->{value}
    );

    $self->output_html( $template->output() );
}

sub _tool_step2 {
    my ( $self, $args ) = @_;
    my $cgi = $self->{'cgi'};

    my $sth;
    my $config_table = $self->get_qualified_table_name($config_table);

    my $hostname = $cgi->param('hostname');
    $sth = C4::Context->dbh->prepare(
        qq| UPDATE $config_table SET value = ? WHERE name = 'HOST_NAME' |);
    $sth->execute($hostname)
      or die "Could not update HOST_NAME in config table";

    my $interval_day = $cgi->param('interval_day');
    $sth = C4::Context->dbh->prepare(
qq| UPDATE $config_table SET value = ? WHERE name = 'ITEM_INTERVAL_DAY' |
    );
    $sth->execute($interval_day)
      or die "Could not update ITEM_INTERVAL_DAY in config table";

    my $encryption_key = $cgi->param('encryption_key');
    $sth = C4::Context->dbh->prepare(
        qq| UPDATE $config_table SET value = ? WHERE name = 'ENCRYPTION_KEY' |);
    $sth->execute($encryption_key)
      or die "Could not update ENCRYPTION_KEY in config table";

    $self->_tool_step1();
}

sub _dir() {
    my ($self) = @_;

    return C4::Context->config('upload_path') . '/' . $upload_path;
}

sub _prepareopacuserjs() {
    my ($self) = @_;

    my $opacuserjs = C4::Context->preference('opacuserjs');
    $opacuserjs =~
s/\/\* JS for Koha Ebook Checkout Plugin.*End of JS for Koha Ebook Checkout Plugin \*\///gs;

    return $opacuserjs;
}

sub _get_session {
    my ($self) = @_;
    my $cgi = $self->{cgi};

    my $session_id = $cgi->cookie("CGISESSID");

    return undef unless $session_id;

    my ( $return, $session ) = C4::Auth::check_cookie_auth($session_id);

    return undef unless $return eq "ok";

    return $session;
}

sub _getbiblionumber {
    my ( $self, $barcode ) = @_;

    my $item = Koha::Items->search( { barcode => $barcode } )->next;
    return $item->biblionumber if $item;
}

sub _getprivateebook {
    my ( $self, $biblionumber ) = @_;

    my $xml = C4::Biblio::GetXmlBiblio($biblionumber);
    $xml = XMLin($xml);
    my $datafield = $xml->{datafield};
    my ($privateebook) =
      grep { $_->{tag} eq 857 && $_->{subfield}->{code} eq 'u' } @$datafield;

    return $privateebook->{subfield}->{content};
}

sub _get_private_ebook_file_record {
    my ( $self, $biblionumber ) = @_;

    my $ebookurl = $self->_getprivateebook($biblionumber) || '';
    my $hash     = ( split( /\?id=/, $ebookurl ) )[1];

    return $self->_get_uploaded_file($hash);
}

sub _get_uploaded_file {
    my ( $self, $hashvalue ) = @_;

    return Koha::UploadedFiles->search(
        {
            hashvalue => $hashvalue,
            public    => 1,
        }
    )->next;
}

sub hasprivateebook {
    my ( $self, $biblionumber ) = @_;

    return $self->_getprivateebook($biblionumber) ? 1 : 0;
}

sub opacdetail {
    my ( $self, $biblionumber ) = @_;
    my $cgi = $self->{cgi};

    my $session  = $self->_get_session();
    my $template = $self->get_template( { file => 'opac-detail.tt' } );
    $template->param( loggedin => $session ? 1 : 0, );

    $self->output_html( $template->output() );
}

sub opacuser {
    my ($self) = @_;
    my $cgi = $self->{cgi};

    my $session  = $self->_get_session();
    my $template = $self->get_template( { file => 'opac-user.tt' } );
    $template->param( loggedin => $session ? 1 : 0, );

    $self->output_html( $template->output() );
}

sub getlinks {
    my ($self) = @_;
    my $cgi = $self->{cgi};

    my $session = $self->_get_session();
    if ($session) {
        my $checkouts_table = $self->get_qualified_table_name($checkouts_table);
        my $config_table    = $self->get_qualified_table_name($config_table);
        my $checkouts       = C4::Context->dbh->selectall_arrayref(
            qq|
            SELECT CONCAT(conf.value, '/', co.uuid) as link, co.access_code, it.barcode FROM items it
            INNER JOIN issues iss ON iss.itemnumber=it.itemnumber
            INNER JOIN $checkouts_table co ON co.issue_id=iss.issue_id
            LEFT JOIN $config_table conf ON conf.name = 'HOST_NAME'
            WHERE iss.borrowernumber=?;
        |, { Slice => {} }, $session->param("number")
        );
        return ( {}, $checkouts );
    }
    return ( { "UNAUTHORIZED" => 1 } );
}

sub ebookcheckout {
    my ( $self, $barcode ) = @_;
    my $cgi = $self->{cgi};

    my $session = $self->_get_session();

    return ( { "UNAUTHORIZED" => 1 } ) unless $session;

    my $biblionumber = $self->_getbiblionumber($barcode);

    return ( { "UNKNOWN_BARCODE" => 1 } ) unless $biblionumber;

    return ( { "NO_PRIVATE_EBOOK" => 1 } )
      unless $self->hasprivateebook($biblionumber);

    my $borrower;
    my $cardnumber = $session->param("cardnumber");
    if ($cardnumber) {
        $borrower = Koha::Patrons->find( { cardnumber => $cardnumber } );
    }

    my ( $impossible, $needconfirm ) =
      CanBookBeIssued( $borrower, $barcode, undef, 0,
        C4::Context->preference("AllowItemsOnHoldCheckoutSCO") );

    if ( scalar keys %$impossible || scalar keys %$needconfirm ) {
        return ( $impossible, $needconfirm );
    }

    my $hold_existed;
    my $item = Koha::Items->find( { barcode => $barcode } );
    if ( C4::Context->preference('HoldFeeMode') eq 'any_time_is_collected' ) {

    # There is no easy way to know if the patron has been charged for this item.
    # So we check if a hold existed for this item before the check in
        $hold_existed = Koha::Holds->search(
            {
                -and => {
                    borrowernumber => $borrower->borrowernumber,
                    -or            => {
                        biblionumber => $item->biblionumber,
                        itemnumber   => $item->itemnumber
                    }
                }
            }
        )->count;
    }

    my $old_issue = Koha::Old::Checkouts->search(
        {
            itemnumber     => $item->itemnumber,
            borrowernumber => $borrower->borrowernumber,
        },
        { order_by => { -desc => 'returndate' } }
    )->next;

    if ($old_issue) {
        my $config_table = $self->get_qualified_table_name($config_table);
        my $interval_day = C4::Context->dbh->selectrow_array(
qq| SELECT value FROM $config_table WHERE name = 'ITEM_INTERVAL_DAY' |
        ) or die "Could not find ITEM_INTERVAL_DAY in config table";
        my $returndate = dt_from_string( $old_issue->returndate, 'sql' );
        my $disallow_until_datetime = $returndate->add( days => $interval_day );
        if (
            DateTime->compare( $disallow_until_datetime, DateTime->now ) != -1 )
        {
            return ( { "CANNOT_CHECKOUT_WITHIN_INTERVAL" => 1 } );
        }
    }

    my $dbh  = C4::Context->dbh;
    my $uuid = uuid();

    my @chars       = ( '0' .. '9', 'A' .. 'Z', 'a' .. 'z' );
    my $access_code = join "", map { $chars[ rand @chars ] } 1 .. 6;

    ( $impossible, my %checkout ) = try {
        my $schema = Koha::Database->schema;
        $schema->txn_do(
            sub {
                my $issue = AddIssue( $borrower, $barcode );
                my $ebook_file_record =
                  $self->_get_private_ebook_file_record($biblionumber);

                my $checkouts_table =
                  $self->get_qualified_table_name($checkouts_table);
                $dbh->do(
qq|INSERT INTO $checkouts_table (uuid, file_hashvalue, issue_id, access_code) VALUES (?, ?, ?, ?)|,
                    undef,
                    $uuid,
                    $ebook_file_record->hashvalue,
                    $issue->issue_id,
                    $access_code
                ) or die { "INSERT_CHECKOUT_FAILED" => $dbh->errstr };
            }
        );

        return ( {}, ( "uuid" => $uuid ) );
    }
    catch {
        # IS: server error
        return ($_);
    };
    return ( $impossible, $needconfirm, %checkout );

    # }
}

sub ebookcheckin {
    my ( $self, $barcode ) = @_;

    my $session = $self->_get_session();
    return ( { "UNAUTHORIZED" => 1 } ) unless $session;

    my $item = Koha::Items->find( { barcode => $barcode } );
    return ( { "ITEM_NOT_FOUND" => 1 } ) unless $item;

    my $checkout = $item->checkout;
    return ( { "CHECKOUT_NOT_FOUND" => 1 } ) unless $checkout;
    return ( { "OVERDUE"            => 1 } ) if $checkout->is_overdue;

    my ( $returned, $messages, $issue ) = AddReturn($barcode);
    return { "CANNOT_CHECK_IN" => 1 } unless $returned;

    return ( {}, $returned );
}

sub unlock {
    my ( $self, $uuid, $access_code ) = @_;
    my $checkouts_table = $self->get_qualified_table_name($checkouts_table);
    my $checkout        = C4::Context->dbh->selectrow_hashref(
        qq|SELECT access_code FROM $checkouts_table WHERE uuid=?|,
        undef, $uuid );

    return { "CHECKOUT_NOT_FOUND"  => 1 } unless $checkout;
    return { "INVALID_ACCESS_CODE" => 1 }
      unless $checkout->{access_code} eq $access_code;

    my $access_token = uuid();

    C4::Context->dbh->do(
        qq|UPDATE $checkouts_table SET access_token=? WHERE uuid=?|,
        undef, $access_token, $uuid )
      or die "Failed to update access_token in $checkouts_table";

    return ( {}, $access_token );
}

sub getebookfilehandle {
    my ( $self, $uuid, $access_token ) = @_;
    my $cgi = $self->{cgi};

    my $checkouts_table = $self->get_qualified_table_name($checkouts_table);
    my $checkout        = C4::Context->dbh->selectrow_hashref(
qq|SELECT access_token, file_hashvalue, issue_id FROM $checkouts_table WHERE uuid=?|,
        undef, $uuid
    );

    return ( { "CHECKOUT_NOT_FOUND" => 1 } ) unless $checkout;
    my $issue = Koha::Checkouts->find( { issue_id => $checkout->{issue_id} } );
    return ( { "OVERDUE"       => 1 } ) if $issue->is_overdue;
    return ( { "INVALID_TOKEN" => 1 } )
      unless $checkout->{access_token} eq $access_token;

    my ( $error, $fh, $encryption_key ) = try {
        my $ebook_file_record =
          $self->_get_uploaded_file( $checkout->{file_hashvalue} );
        my $fh = $ebook_file_record->file_handle
          if $ebook_file_record
          or die { "OPEN_FILE_FAILED" => 1 };
        my $config_table   = $self->get_qualified_table_name($config_table);
        my $encryption_key = C4::Context->dbh->selectrow_array(
            qq| SELECT value FROM $config_table WHERE name = 'ENCRYPTION_KEY' |
        );
        $fh->binmode;
        return ( {}, $fh, $encryption_key );
    }
    catch {
        return ($_);
    };
    return ( $error, $fh, $encryption_key );
}

sub expires {
    my ( $self, $uuid ) = @_;
    my $checkouts_table = $self->get_qualified_table_name($checkouts_table);

    my $date_due = C4::Context->dbh->selectrow_array(
        qq|
        SELECT i.date_due
        FROM issues i
        JOIN $checkouts_table c ON c.issue_id = i.issue_id
        WHERE c.uuid = ?
    |, undef, $uuid
    );

    return { "CHECKOUT_NOT_FOUND" => 1 } unless $date_due;

    return ( {}, dt_from_string( $date_due, 'sql' ) );
}

sub _get_checkout_for_renewal {
    my ( $self, $uuid ) = @_;
    my $checkouts_table = $self->get_qualified_table_name($checkouts_table);

    my $checkout = C4::Context->dbh->selectrow_hashref(
        qq|
        SELECT c.issue_id
        FROM $checkouts_table c
        WHERE c.uuid = ?
    |, undef, $uuid
    );
    my $issue = Koha::Checkouts->search(
        {
            issue_id => $checkout->{issue_id},
        },
    )->next;

    return $issue;
}

sub renewable {
    my ( $self, $uuid ) = @_;

    my $checkout = $self->_get_checkout_for_renewal($uuid);

    return { "CHECKOUT_NOT_FOUND" => 1 } unless $checkout;

    my ($renewable) = CanBookBeRenewed( $checkout->patron, $checkout, );

    return ( {}, $renewable );
}

sub renew {
    my ( $self, $uuid ) = @_;

    my $checkout = $self->_get_checkout_for_renewal($uuid);

    return { "CHECKOUT_NOT_FOUND" => 1 } unless $checkout;

    my ( $renewable, $error ) =
      CanBookBeRenewed( $checkout->patron, $checkout, );

    return { uc($error) => 1 } unless $renewable;

    my $schema = Koha::Database->schema;
    $schema->txn_do(
        sub {
            my $date_due = AddRenewal(
                {
                    borrowernumber => $checkout->borrowernumber,
                    itemnumber     => $checkout->itemnumber,
                    branch         => $checkout->branchcode,
                }
            );

            my $checkout = $self->_get_checkout_for_renewal($uuid);
            my ($renewable) = CanBookBeRenewed( $checkout->patron, $checkout, );

            return ( {}, $date_due, $renewable );
        }
    );
}

1;
