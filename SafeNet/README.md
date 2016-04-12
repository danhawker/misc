# SafeNet

This directory includes some notes and scripts I found/created and used when setting up and using a SafeNet eToken.

## SafeNet Authentication Client (SAC)
Is the client software from SafeNet and fundamentally installs drivers and libraries to enable you to access the eToken.
You need to install this wherever you want to use the eToken. Unfortunately you need a support agreement/login to access the download, or have a bit of a Google. Quite a few corporates and universities have the software available. Strictly you need to license this, but it works fine in Evaluation Mode and you rarely need the Tools anyway, just need to libraries.

I've used both the Linux (on RHEL7) and MacOSX (on El Capitan) with success. Both used SAC v9.2.

## token_pubkey.pl
A Perl script I gleaned from somewhere (Credits says Matt Wilks, <matt.wilks@utoronto.ca> at University of Toronto), which is a useful script to read/retrieve any Public Keys from the eToken. Really useful if you want to retrieve a public key for the appropriate certificate on the token for using with SSH authorized_keys.

#### Setup
On RHEL7 (my workstation OS), you need to enable EPEL and download and install a few RPMs from Fedora to make it all work.

perl-Term-ReadPassword
I downloaded a F19 RPM from the Fedora Koji. https://kojipkgs.fedoraproject.org//packages/perl-Term-ReadPassword/0.11/14.fc19/noarch/perl-Term-ReadPassword-0.11-14.fc19.noarch.rpm
RHEL7 was initially baselined at F19 so RPMs built for F19 generally install easily.

I used `yum localinstall` to install and ensure any dependencies were included.

#### Usage
Simply run `./token_pubkey.pl`

    [dan@behemoth SafeNet]$ ./token_pubkey.pl
    You must specify either --generate or --print

    Usage: gen_pubkey.pl [OPTIONS]
        -l, --library    PKCS#11 library file
        -g, --generate   generate a Public Key Object
        -p, --print      print the SSH RSA public key string
            --openssl    location of the openssl binary
            --pkcs11     location of the pkcs11-tool binary

So, to print a SSH public key string...

    [dan@behemoth SafeNet]$ ./token_pubkey.pl --print
    PIN:

    Certificates present on your token:

      ID                Label             Types
      --------------------------------------------------------------------------------
       1.               01  dan@behemoth.pv.lan  (Private Key, Public Key, Certificate)

    Which ID would you like to print the public key for? (1 or 'exit' for none) 1
    Using slot 0 with a present token (0x0)
    Copy and paste this text into your .ssh/authorized_keys file on each remote SSH host:

    ssh-rsa AAAAB3<snipped_output>EoYuz68E/

    Cleaning up...

Cool :)

## Using SSH
This is surprisingly simple, you need to add an additional pkcs11 engine to OpenSSL, but once done it 'just works'.

#### Setup
Again I needed to add some non-standard (for RHEL) RPMs so I grabbed them from Fedora Koji.
engine_pkcs11 is a pkcs11 engine for OpenSSL.
https://kojipkgs.fedoraproject.org//packages/engine_pkcs11/0.1.8/9.fc21/x86_64/engine_pkcs11-0.1.8-9.fc21.x86_64.rpm
libp11 is a dependency for above and simply adds a abstraction layer to the underlying pkcs11 infrastructure, making it easier to use.
https://kojipkgs.fedoraproject.org//packages/libp11/0.2.8/6.fc21/x86_64/libp11-0.2.8-6.fc21.x86_64.rpm

#### Usage
Simply copy the SSH public key (as gleaned above), to the target system/user(s) authorized_keys file, and then SSH to it, telling OpenSSH that you want to use the eToken library.
In this example, I am accessing my ReadyNAS at home.

    [dan@behemoth SafeNet]$ ssh -I /usr/lib64/libeToken.so root@serapeum
    Enter PIN for 'danhawker':
    Last login: Mon Apr 11 22:23:00 2016 from behemoth.pv.lan
    Last login: Mon Apr 11 22:26:04 2016 from behemoth.pv.lan on pts/0
    Linux serapeum 2.6.37.6.RNx86_32.1.4 #1 Thu May 28 16:18:23 PDT 2015 i686 GNU/Linux
    serapeum:~#

If you use ssh-agent, this is should be doable, however with very little digging, I found that the `SSH_AUTH_SOCK` env_var kept moving about and generally not setting itself correctly (keyring was trying to be clever).
This website https://r3blog.nl/index.php/etoken-pro-72k/ has a few options, but as I don't find it too tedious, I haven't bothered fixing it yet.

The two bash scripts (ssh_wrapper.sh and get_pkcs11_ssh_keys.sh) are from that site.

So it seems that Gnome-Keyring doesn't support adding from PKCS11 modules, so you need to disable it. Seems a bit silly.

#### etoken.sh
This setup bash script I found on [Github](https://gist.github.com/mclap/2039776)
