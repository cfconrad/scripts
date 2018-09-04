#!/usr/bin/perl -w

use strict;
use warnings;
use Getopt::Long;

my $image            = undef;
my $service_acc_file = $ENV{AZURE_AUTH_LOCATION};
my $ssh_key          = '~/.ssh/id_rsa';
my $region           = 'westeurope';
my $tests            = 'test_sles_wait_on_registration test_sles test_sles_azure';
my $dry              = 0;
my $nocleanup        = 0;
my $man              = 0;
my $help             = 0;


GetOptions("dry" => \$dry,
    "image=s"    => \$image,
    "no-cleanup" => \$nocleanup,
    "acc-file=s" => \$service_acc_file,
    "ssh-key=s"  => \$ssh_key,
    "tests=s"    => \$tests
);

unless ($image) {
    print("Missing mandatory parameter --image$/");
    exit(2);
}

$nocleanup = $nocleanup ? "--no-cleanup " : "";

my $cmd = "ipa test azure --distro sles -i $image "
  . "--service-account-file $service_acc_file "
  . "--ssh-private-key-file $ssh_key "
  . "--region $region "
  . $nocleanup
  . $tests;

print $cmd . $/;
if (!$dry) {
    system($cmd);
}
