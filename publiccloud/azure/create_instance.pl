#!/usr/bin/perl -w

use strict;
use warnings;
use Getopt::Long;
use Pod::Usage qw(pod2usage);

my $prefix         = "cfc";
my $resource_name  = "$prefix-" . time();
my $image          = undef;
my $username       = undef;
my $password       = undef;
my $ssh_pub_key    = "~/.ssh/id_rsa.pub";
my $linux_username = 'azureuser';
my $location       = "westeurope",
  my $man          = 0;
my $help = 0;

GetOptions('image=s' => \$image,
    'resource-name=s'  => \$resource_name,
    'username=s'       => \$username,
    'password=s'       => \$password,
    'ssh-pub=s'        => \$ssh_pub_key,
    'linux-username=s' => \$linux_username,
    'prefix=s'         => \$prefix,
    'location=s'       => \$location,
    'help'             => \$help,
    'man'              => \$man
);

pod2usage(1) if $help;
pod2usage(-verbose => 2) if $man;
pod2usage("Missing mandatory parameter --image") unless ($image);

if ($username || $password) {
    pod2usage("Missing parameter --username") unless ($username);
    pod2usage("Missing parameter --password") unless ($password);
    system("az login -u $username -p $password") == 0
      or die("login");
}

# Create a resource group.
system("az group create --name $resource_name --location $location") == 0
  or die("group create");

# Create a virtual network.
system("az network vnet create --resource-group $resource_name --name $prefix-vnet --subnet-name $prefix-subnet") == 0
  or die("network vnet create");

# Create a public IP address.
system("az network public-ip create --resource-group $resource_name --name $prefix-pubip") == 0
  or die("network public-ip");

# Create a network security group.
system("az network nsg create --resource-group $resource_name --name $prefix-secgroup") == 0
  or die("network nsg create");

# Create a virtual network card and associate with public IP address and NSG.
system("az network nic create --resource-group $resource_name --name $prefix-nic --vnet-name $prefix-vnet --subnet $prefix-subnet --network-security-group $prefix-secgroup --public-ip-address $prefix-pubip") == 0
  or die("network nic create");

# Create a new virtual machine, this creates SSH keys if not present.
system("az vm create --resource-group $resource_name --name $prefix-vm --nics $prefix-nic --image $image --ssh-key-value $ssh_pub_key --admin-username $linux_username") == 0
  or die("vm create");

# Open port 22 to allow SSh traffic to host.
system("az vm open-port --port 22 --resource-group $resource_name --name $prefix-vm") == 0
  or die("vm open-port");


__END__

=head1 NAME

create_instance.pl - example on how to create azure instance with given parameters

=head1 SYNOPSIS

create_instance.pl [options]

=head1 OPTIONS

=over 4

=item B<--image>

Unique image name (mandatory)

=item B<--prefix>

This prefix is used to create the resouce name and a lot of resources like ip,
subnet and secgroup.

=item B<--username>

If username and password is given, a azure login gets invoked before creating the VM.

=item B<--password>

If username and password is given, a azure login gets invoked before creating the VM.

=item B<--ssh-pub>

The ssh public key, which will be installed on that VM (default: ~/.ssh/id_rsa.pub)

=item B<--linux-username>

The name of the user which is created in the VM (default: azureuser)

=item B<--location>

Name of the location (default: westeurope)

=back

=head1 DESCRIPTION

This script create a VM on azure with some default parameters. The only mandatory
parameter is B<--image>.

Caution there is no cleanup on failure!

=cut

