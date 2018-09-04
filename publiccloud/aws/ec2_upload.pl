#!/usr/bin/perl -w

use strict;
use warnings;
use Getopt::Long;
use Pod::Usage qw(pod2usage);

sub find_ami {
    my ($name) = @_;

    my $out = `aws ec2 describe-images  --filters 'Name=name,Values=$name'`;
    if ($out =~ /"ImageId":\s+"([^"]+)"/) {
        return $1;
    }
    return;
}

MAIN:
{
    my $key_id          = $ENV{AWS_ACCESS_KEY_ID};
    my $key_secret      = $ENV{AWS_SECRET_ACCESS_KEY};
    my $region          = $ENV{AWS_DEFAULT_REGION} || 'eu-central-1';
    my $man             = 0;
    my $help            = 0;
    my $ssh_key_pair    = undef;
    my $file            = undef;
    my $ssh_private_key = "~/.ssh/id_rsa";

    GetOptions('file=s' => \$file,
        'key-id=s'          => \$key_id,
        'key-secret=s'      => \$key_secret,
        'region=s'          => \$region,
        'ssh-key-pair=s'    => \$ssh_key_pair,
        'ssh-private-key=s' => \$ssh_private_key,
        'help'              => \$help,
        'man'               => \$man
    );

    pod2usage(1) if $help;
    pod2usage(-verbose => 2) if $man;

    pod2usage("Missing mandatory parameter --file")         unless ($file);
    pod2usage("Missing mandatory parameter --ssh-key-pair") unless ($ssh_key_pair);

    my ($image_name) = $file =~ '([^/]+)$';

    my $ami_id = find_ami($image_name);
    if (!defined($ami_id)) {
        print("Try uploading image!!$/");
        my $cmd
          = "ec2uploadimg --access-id '"
          . $key_id
          . "' -s '"
          . $key_secret . "' "
          . "--backing-store ssd "
          . "--grub2 "
          . "--machine 'x86_64' "
          . "-n '$image_name' "
          . (($image_name =~ /hvm/i) ? "--virt-type hvm --sriov-support " : "--virt-type para ")
          . "--verbose "
          . "--regions '$region' "
          . "--ssh-key-pair '$ssh_key_pair' "
          . "--private-key-file '$ssh_private_key' "
          . "-d 'OpenQA tests' "
          . "'$file'";
        system($cmd);
        $ami_id = find_ami($image_name);
    } else {
        print("Image with this name $image_name already exists!$/");
    }

    if ($ami_id) {
        print("IMAGE AMI:$ami_id$/");
    }
}

__END__

=head1 NAME

ec2_upload.pl - wrapper for ec2upladimg

=head1 SYNOPSIS

ec2_upload.pl --file <path> [options]

=head1 OPTIONS

=over 4

=item B<--image>

Path to the image file (mandatory)

=item B<--key-id>

AWS access key id or read from environment B<AWS_ACCESS_KEY_ID>

=item B<--key-secret>

AWS access secret or read from environment B<AWS_SECRET_ACCESS_KEY>

=item B<--region>

The region to upload image to or read from environment B<AWS_DEFAULT_REGION>
(default: eu-central-1)

=item B<--ssh-key-pair>

Name of the key-pair on aws

=item B<--ssh-private-key>

Corresponding private ssh key

=back

=head1 DESCRIPTION

Upload a image corresponding to its name to AWS and print the AMI.

For sriov see https://docs.aws.amazon.com/en_en/AWSEC2/latest/UserGuide/sriov-networking.html

=cut
