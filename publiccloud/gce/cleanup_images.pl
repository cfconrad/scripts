#!/usr/bin/perl

use Mojo::Base -strict;
use Mojo::JSON qw(decode_json encode_json);
use Data::Dumper;
use Sort::Versions;
use Term::ANSIColor;

my $BUCKET='gs://openqa-suse-de';
my $KEEP_IMAGES = 1;

sub color_delete { return color('bold red') . shift . color('reset'); }
sub color_keep { return color('bold green') . shift . color('reset'); }

sub main()
{
    # Clean up blobs
    my $images = {};
    my $out = qx(gsutil ls $BUCKET);
    for my $l (split(/\s*\r?\n\s*/, $out)){
        my $img = substr($l, length($BUCKET)+1);
        if ($img =~ /SLES(?<version>\d+(-SP\d+)?)-GCE(-(?<flavor>BYOS|On-Demand))?\.x86_64-(?<kiwi>\d+\.\d+\.\d+)-Build(?<build>\d+\.\d+)\.tar\.gz/){
            print color('black on_bright_red') . "Delete old format " . $l . color('reset') . $/;
            qx(gsutil rm $l);
        }
        elsif ($img =~ /SLES(?<version>\d+(-SP\d+)?)-GCE\.x86_64-(?<kiwi>\d+\.\d+\.\d+)(-(?<flavor>BYOS|On-Demand))-Build(?<build>\d+\.\d+)\.tar\.gz/){
            my $e = {
                build => $+{kiwi} . '-' . $+{build},
                version => $+{version},
                flavor => $+{flavor},
                link => $l,
            };
            my $key = $+{version} . "-" . $+{flavor};
            $images->{$key} //= [];
            push (@{$images->{$key}}, $e);
        }
    }
    for my $key (keys %{$images}){
        my @sorted_data = sort { versioncmp($a->{build}, $b->{build})} @{$images->{$key}};
        for(my $i = 0; $i < @sorted_data; $i++){
            my $link = $sorted_data[$i]->{link};
            if ($i < @sorted_data - $KEEP_IMAGES){
                print color_delete("DEL  ") . $link . $/;
                qx(gsutil rm $link);
            }
            else {
                print color_keep("KEEP ") . $link . $/;
            }
        }
    }

    #cleanup images
    $images = {};
    my $online_images = qx(gcloud --format json compute images list  --no-standard-images);
    $online_images = decode_json($online_images);
    for my $i (@{$online_images}){
        #sles12-sp5-gce-x8664-0-9-1-byos-build1-55
        if ($i->{name} =~ m/sles(?<version>\d+(-sp\d+)?)-gce-(?<arch>[^-]+)-(?<kiwi>\d+-\d+-\d+)-(?<flavor>byos|on-demand)-build(?<build>\d+-\d+)/){
            my $key = join('-', $+{version}, $+{flavor});
            my $e = {
                name => $i->{name},
                selfLink => $i->{selfLink},
                build => join('-', $+{kiwi}, $+{build})
            };
            $images->{$key} //= [];
            push(@{$images->{$key}}, $e);
        } else {
            print(color_delete('DELETE old format ') . $i->{name} .$/);
            my $link = $i->{selfLink};
            qx(gcloud --quiet compute images delete $link);
        }
    }
    for my $key (keys %{$images}){
        my @sorted_data = sort { versioncmp($a->{build}, $b->{build})} @{$images->{$key}};
        for(my $i = 0; $i < @sorted_data; $i++){
            my $link = $sorted_data[$i]->{selfLink};
            my $name = $sorted_data[$i]->{name};
            if ($i < @sorted_data - $KEEP_IMAGES){
                print color_delete("DEL  ") . 'Image:' . $name . $/;
                qx(gcloud --quiet compute images delete $link);
            }
            else {
                print color_keep("KEEP ") . 'Image: ' . $name . $/;
            }
        }
    }
    return 0;
}

exit main();
