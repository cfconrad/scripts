use Mojo::Base 'base';
use Mojo::JSON qw(decode_json encode_json);
use Date::Parse;
use Mojo::File 'path';
use Data::Dumper;
use Sort::Versions;
use Term::ANSIColor;

my $keep_img = 1;
my $dry_run = 1;
my $IMAGE_MAX_AGE = 60 * 60 * 24 * 30;


sub color_delete { return color('bold red') . shift . color('reset'); }
sub color_keep { return color('bold green') . shift . color('reset'); }

sub run {
    my ($cmd) = @_;
    print ("RUN:    " . $cmd . $/);
    my $out = `$cmd`;
    die(color_delete("FAILED:") . $cmd) if ($?);
    return $out;
}

sub parse_images
{
    my $data = shift;
    my $images = {};
    for my $i (@{$data->{Images}}){
        # openqa-SLES12-SP5-EC2.x86_64-0.9.1-BYOS-Build1.55.raw.xz
        if ($i->{Name} =~ /openqa-SLES(?<version>\d+(-SP\d+)?)-EC2\.(?<arch>x86_64)-(?<kiwi>\d+\.\d+\.\d+)-(?<flavor>BYOS|On-Demand)-Build(?<build>\d+\.\d+)\.raw\.xz/){
            my $key = join('-', $+{version}, $+{flavor});
            my $entry = {
                build => join('-', $+{kiwi}, $+{build}),
                name => $i->{Name},
                creation_time => str2time($i->{CreationDate}),
                ami => $i->{ImageId},
                delete_me => 0
            };
            $images->{$key} //= [];
            push (@{$images->{$key}}, $entry);
        } else {
            print color_delete("UNKNOWN image: " . $i->{Name} . $/);
        }
    }
    for my $key (keys %{$images}){
        my @sorted_data = sort {versioncmp($a->{build},$b->{build})} @{$images->{$key}};
        for(my $i = 0; $i < @sorted_data; $i++){
            my $entry = $sorted_data[$i];
            # Mark all older images to be deleted
            $entry->{delete_me} = 1 if ($i < @sorted_data - $keep_img);
            $entry->{delete_me} = 1 if ($entry->{creation_time} < time() - 3600 * 24 * 30);
        }
        $images->{$key} = \@sorted_data;
    }
    return $images;
}

# delete ami's
my $data = decode_json(run("aws ec2 describe-images --owners self "));
my $images = parse_images($data);
for my $key (keys %{$images}){
    for my $image (@{$images->{$key}}){
        if ($images->{delete_me}){
            print(color_delete("DELETE: ") . $image->{name} . $/);
            run("aws ec2 deregister-image --image-id '" . $image->{ami} . "'") unless ($dry_run);
        } else {
            print(color_keep("Keep:   ") . $image->{name} . $/);
        }
    }
}

# cleanup key-pairs
$data = decode_json(run("aws ec2 describe-key-pairs"));
my $instances = decode_json(run("aws ec2 describe-instances"));
my @used_keys = map {$_->{KeyName}} @{$instances->{Reservations}->[0]->{Instances}};
for my $key (@{$data->{KeyPairs}}){
    my $name = $key->{KeyName};
    if ($name =~ /^openqa-/ && ! grep (/^$name$/, @used_keys) ){
        print(color_delete("DELETE: ") . "Key: " . $name);
        run("aws ec2 delete-key-pair --key-name '$name'") unless ($dry_run);
    }
}
