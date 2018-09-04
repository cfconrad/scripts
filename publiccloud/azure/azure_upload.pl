#!/usr/bin/perl -w

use strict;
use warnings;
use Mojo::JSON qw(decode_json encode_json);
use Data::Dumper;
use Getopt::Long;
use Pod::Usage qw(pod2usage);

sub cmd
{
    my ($cmd) = @_;

    print $cmd . $/;
    my $output = `$cmd`;

    wantarray ? ($?, $output) : $?;
}

sub assert
{
    my ($cmd) = @_;

    my ($retval, $output) = cmd($cmd);
    $retval == 0 or die($cmd);
    return $output;
}

sub find_blob
{
    my ($name, $acc, $key, $container) = @_;

    my ($ret, $output) = cmd("az storage blob list --account-name $acc --account-key $key --container-name $container ");
    return unless $ret == 0;

    my $json = decode_json($output);

    for my $blob (@{$json}) {
        if ($blob->{name} eq $name) {
            return $blob;
        }
    }
    return;
}

#az login
#az account set --subscription
#az group create --name A_GROUP_NAME_OF_YOUR_CHOOSING -l A_REGION_OF_YOUR_CHOOSING
#az storage account create --resource-group GROUP_NAME_FROM_PREVIOUS_STEP -l REGION_FROM_PREVIOUS_STEP --name ACCOUNT_NAME_OF_YOUR_CHOOSING --kind Storage --sku Standard_LRS
#az storage account keys list --resource-group THE_GROUP_NAME --account-name ACCOUNT_NAME
#az storage container create --account-name ACCOUNT_NAME --name CONTAINER_NAME_OF_YOUR_CHOOSING
#az storage blob upload --max-connections 4  --account-name ACCOUNT_NAME --account-key KEY_FROM_ABOVE --container-name CONTAINER_NAME --type page --file FILE_NAME.vhdfixed --name A_BLOB_NAME_OF_YOUR_CHOOSING.vhd
#az disk create --resource-group GROUP_NAME --name DISK_NAME_OF_YOUR_CHOOSING --source https://rACCOUNT_NAM.blob.core.windows.net/DISK_NAME/BLOB_NAME.vhd
#az image create --resource-group GROUP_NAME --name IMAGE_NAME_OF_YOUR_CHOOSING --os-type Linux --source='DISK_NAME'
#az vm create --resource-group  --location  --name  --image --admin-username  --ssh-key-value


my $username = undef;
my $password = undef;

my $region   = 'westeurope';
my $img_file = undef;
my $prefix   = 'prefix';
my $man      = 0;
my $help     = 0;

GetOptions('username=s' => \$username,
    'password=s' => \$password,
    'prefix=s'   => \$prefix,
    'file=s'     => \$img_file,
    'region=s'   => \$region,
    'help'       => \$help,
    'man'        => \$man
);

pod2usage(1) if $help;
pod2usage(-verbose => 2) if $man;

pod2usage("Missing mandatory parameter --file") unless ($img_file);
die("File not found") unless (-f $img_file);

my ($img_name) = $img_file =~ /([^\/]+)$/;
$img_name =~ s/vhdfixed$/vhd/;
my $suffix = time();
my $group  = $prefix . "-" . $img_name;
my $acc    = $prefix . "-" . $suffix;
$acc =~ s/[^\da-zA-Z]//;
$acc = substr($acc, 0, 24);
my $container = $prefix . "-" . $suffix;
my $disk_name = $prefix . "-" . $suffix;

if ($username && $password) {
    assert("az login -u $username -p $password");
}

assert("az group create --name $group -l $region");

assert("az storage account create --resource-group $group -l $region --name $acc --kind Storage --sku Standard_LRS");

my $output = assert("az storage account keys list --resource-group $group --account-name $acc");
my $json   = decode_json($output);
my $key    = undef;
if (@{$json} > 0) {
    $key = $json->[0]->{value};
}
die("No key found!") unless $key;

unless (find_blob($img_name, $acc, $key, $container)) {
    assert("az storage container create --account-name $acc --name $container");

    assert("az storage blob upload --max-connections 4  --account-name $acc --account-key $key --container-name $container --type page --file $img_file --name $img_name");
}

assert("az disk create --resource-group $group --name $disk_name --source https://$acc.blob.core.windows.net/$container/$img_name");

assert("az image create --resource-group $group --name $img_name --os-type Linux --source='$disk_name'");


__END__

=head1 NAME

azure_upload.pl - upload image to azure

=head1 SYNOPSIS

azure_upload.pl --file <filename> [options]

=head1 OPTIONS

=over 4

=item B<--file>

Path to file which will be uploaded. The file should end with B<*.vhdfixed>.

=item B<--region>

Specify region (default: weteurope)

=item B<--prefix>

This prefix will be used for all resources (default:prefix)

=item B<--username>

If username and password is given, the azure login gets done.

=item B<--password>

If username and password is given, the azure login gets done.

