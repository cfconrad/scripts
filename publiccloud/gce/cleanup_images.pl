#!/usr/bin/perl

use Mojo::Base -strict;
use Data::Dumper;
use Sort::Versions;
use Term::ANSIColor;

my $BUCKET='gs://openqa-suse-de';
my $KEEP_IMAGES = 1;

sub main()
{
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
                print color('bold red') . "DEL  " . color('reset') . $link . $/;
                qx(gsutil rm $link);
            }
            else {
                print color('bold green') . "KEEP " . color('reset') . $link . $/;
            }
        }
    }

    return 0;
}

exit main();
