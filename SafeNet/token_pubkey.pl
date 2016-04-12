#!/usr/bin/perl -w
#
# $Id: gen_pubkey.pl,v 1.1 2013/04/12 13:10:53 matt Exp matt $
#
# Matt Wilks, <matt.wilks@utoronto.ca>
# I+TS, Information Security & Enterprise Architecture
# University of Toronto
#
# This script will attempt to find the SafeNet eToken library automatically
# based on 32 or 64-bit OS.  You may also specify an alternate library with the
# --library switch and the full path to your library .so or .dylib file.
#
# Term::ReadPassword can be installed with:
#
#   ubuntu# sudo apt-get install libterm-readpassword-perl
#   fedora# sudo yum install perl-Term-ReadPassword
#
# or, if all else fails:
#
#   nix# sudo cpan install Term::ReadPassword
#

use strict;
use Getopt::Long;
use Term::ReadPassword;

my $DER    = "/tmp/gen_pubkey.der";
my $PEM    = "/tmp/gen_pubkey.pem";
my $PUBKEY = "/tmp/gen_pubkey.key";

my $TOKEN_LIB  = '';
my $ETOKEN_32  = "/usr/lib/libeToken.so";
my $ETOKEN_64  = "/usr/lib64/libeToken.so";
my $ETOKEN_MAC = "/usr/local/lib/libeToken.dylib";
my $OBJECTS    = ();
my $LABELS     = ();
my $PIN        = '';
my $ID         = '';

my $USER_LIB = '';
my $MODE     = '';
my $GENERATE = 0;
my $PRINT    = 0;
my $OPENSSL  = '';
my $PKCS11   = '';
my $result = GetOptions(
    "library|l:s" => \$USER_LIB,
    "generate|g"  => \$GENERATE,
    "print|p"     => \$PRINT,
    "openssl"     => \$OPENSSL,
    "pkcs11"      => \$PKCS11,
);
if (!$result) {
    usage_die("error parsing options");
}

if ($USER_LIB ne '') {
    if (! -f $USER_LIB) {
        usage_die("cannot find PKCS#11 library in $USER_LIB");
    }
}
else {
    if (-f $ETOKEN_32) {
        $TOKEN_LIB = $ETOKEN_32;
    }
    elsif (-f $ETOKEN_64) {
        $TOKEN_LIB = $ETOKEN_64;
    }
    elsif (-f $ETOKEN_MAC) {
        $TOKEN_LIB = $ETOKEN_MAC;
    }
    else {
        die "cannot find library for SafeNet eTokens in /usr/lib/libeToken.so or /usr/lib64/libeToken.so";
    }
}

if ($OPENSSL eq '') {
    $OPENSSL = `which openssl`; chomp($OPENSSL);
    if ($OPENSSL eq '') {
        usage_die("cannot find openssl binary; specify its location with --openssl");
    }
}

if ($PKCS11 eq '') {
    $PKCS11 = `which pkcs11-tool`; chomp($PKCS11);
    if ($PKCS11 eq '') {
        usage_die("cannot find pkcs11-tool binary; ensure that you have OpenSC installed");
    }
}

if ($PRINT) {
    $MODE = 'print';
}
elsif ($GENERATE) {
    $MODE = 'generate';
}
else {
    usage_die("You must specify either --generate or --print");
}

# Begin main program
#
$|=1;

$PIN = read_password('PIN: ');
redo unless ($PIN ne ''); print "\n";

sc_login() || die "Incorrect PIN\n";
sc_get_contents();
$ID = get_choice();
sc_get_cert($ID);
der_cert_to_pem_pubkey();

if ($MODE eq 'generate') {
    pem_pubkey_to_der_pubkey();
    sc_write_pubkey($ID);

    print "Successfully wrote public key onto certificate.\n";
}

print "Copy and paste this text into your .ssh/authorized_keys file on each\n";
print "remote SSH host:\n\n";
print_ssh_pubkey();

print "\nCleaning up...\n\n";
system("rm -f $DER $PEM $PUBKEY");

sub print_ssh_pubkey {
    system("ssh-keygen -i -m PKCS8 -f $PEM");
}

sub get_choice {
    my $mapping = ();
    my $i = 0;

    print "Certificates present on your token:\n\n";
    printf("  %-3s %-16s  %-16s  %-s\n", '', 'ID', 'Label', 'Types');
    print "  " . "-" x 80 . "\n";
    foreach my $id (keys %{$OBJECTS}) {
        my $pubkey = grep(/Public Key/, @{$OBJECTS->{$id}});

        # The given certificate can be selected if:
        #
        #     1. We are generating and there isn't a public key object
        #     2. We are printing and there is a public key object
        #
        if (($MODE eq 'generate' && !$pubkey) || ($MODE eq 'print' && $pubkey)) {
            #if (!grep(/Public Key/, @{$OBJECTS->{$id}})) {
            $i++;
            printf("  %2s. %16s  %16s  (%s)\n", $i, $id, $LABELS->{$id}, join(", ", @{$OBJECTS->{$id}}));
            $mapping->{$i} = $id;
        }
        else {
            printf("  %3s %16s  %16s  (%s)\n", '', $id, $LABELS->{$id}, join(", ", @{$OBJECTS->{$id}}));
        }
    }
    print "\n";

    if ($i == 0) {
        print "There are no available IDs to $MODE a public key for, exiting...\n";
        exit(0);
    }
    else {
        if ($MODE eq 'generate') {
            print "(You cannot generate a public key for an ID that already has one)\n";
            print "Which ID would you like to generate a public key for? ";
        }
        elsif ($MODE eq 'print') {
            print "Which ID would you like to print the public key for? ";
        }

        if ($i == 1) {
            print "(1 or 'exit' for none) ";
        }
        else {
            print "(1-$i or 'exit' for none) ";
        }
        my $choice = <STDIN>; chomp($choice);
        if ($choice =~ /exit/i || $choice eq '') {
            print "Exiting...\n";
            exit(0);
        }
        if ($choice !~ /^\d+$/ || $choice < 1 || $choice > $i) {
            print "Invalid choice: $choice\n";
            exit(1);
        }
        my $ID = $mapping->{$choice};
    }
}

# Test the PIN supplied to make sure that it can unlock the token.
# Returns 1 for success, 0 for failure.
#
sub sc_login {
    `$PKCS11 --module $TOKEN_LIB -l -p $PIN -L 2>&1 /dev/null`;
    return ($? == 0) ? 1 : 0;
}

# List the contents of the token and store it in a hash of arrays.
#
sub sc_get_contents {
    my @output = `$PKCS11 --module $TOKEN_LIB -l -p $PIN -O 2>&1`;

    my $in_object = 0;
    my $type  = '';
    my $id    = '';
    my $label = '';

    foreach my $line (@output) {
        $line =~ s/^\s+//;
        if ($line =~ /^(Private Key|Public Key|Certificate)/) {
            if ($in_object) {
                if (!defined($OBJECTS->{$id})) {
                    $OBJECTS->{$id} = [];
                }
                push @{$OBJECTS->{$id}}, $type;
                if (!defined($LABELS->{$id}) && $label ne '') {
                    $LABELS->{$id} = $label;
                }
                $id    = '';
                $label = '';
            }
            else {
                $in_object = 1;
            }
            $type = $1;
        }
        elsif ($line =~ /^ID:\s+(.*)/) {
            $id = $1;
        }
        elsif ($line =~ /^label:\s+(.*)/ && $label eq '') {
            $label = $1;
        }
    }
    if ($id ne '') {
        if (!defined($OBJECTS->{$id})) {
            $OBJECTS->{$id} = [];
        }
        push @{$OBJECTS->{$id}}, $type;
        if (!defined($LABELS->{$id}) && $label ne '') {
            $LABELS->{$id} = $label;
        }
    }
}

# Fetch the certificate with the specified ID off of the smartcard.
#
sub sc_get_cert {
    my $ID = shift || return 0;
    my $result = system("$PKCS11 --module $TOKEN_LIB -l -p $PIN --read-object --type cert --id $ID > $DER");
    return ($result == 0) ? 1 : 0;
}

# Write the public key with the specified ID onto the smartcard.
#
sub sc_write_pubkey {
    my $ID = shift || return 0;
    my $result = system("$PKCS11 --module $TOKEN_LIB -l -p $PIN --write-object $PUBKEY --type pubkey --id $ID");
}

# Extract the PEM formatted public key from the DER formatted certificate.
#
sub der_cert_to_pem_pubkey {
    my $result = system("$OPENSSL x509 -in $DER -inform DER -pubkey -noout > $PEM");
    return ($result == 0) ? 1 : 0;
}

# Convert the PEM formatted public key into a DER formatted public key.
#
sub pem_pubkey_to_der_pubkey {
    my $result = system("$OPENSSL rsa -pubin -in $PEM -inform PEM -pubout -outform DER -out $PUBKEY");
}

sub usage_die {
    my $mesg = shift || '';
    print "$mesg\n\n";
    print "Usage: gen_pubkey.pl [OPTIONS]\n";
    print "    -l, --library    PKCS#11 library file\n";
    print "    -g, --generate   generate a Public Key Object\n";
    print "    -p, --print      print the SSH RSA public key string\n";
    print "        --openssl    location of the openssl binary\n";
    print "        --pkcs11     location of the pkcs11-tool binary\n";
    exit 1;
}
