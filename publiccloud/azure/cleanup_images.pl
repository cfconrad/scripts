use Mojo::Base 'base';
use Mojo::JSON qw(decode_json encode_json);
use Date::Parse;
use Mojo::File 'path';
use Data::Dumper;

my $rgroup = 'openqa-upload';
my $storage_acc = 'openqa';
my $storage_container = 'sle-images';
my $keep_img = 1;

sub run {
    my ($cmd) = @_;
    print (" RUN: " . $cmd . $/);
    my $out = `$cmd`;
    die("FAILED: $cmd") if ($?);
    return $out;
}

sub annotate_images
{
    my ($data) = @_;
    my $img_by_group = {};
    my $ret = {};
    for my $i (@{$data}){
        #            'name' => 'SLES12-SP5-Azure.x86_64-0.1.0-BYOS-Build1.14.vhd',
        my $name = $i->{name};
        my ($prefix, $build) = $name =~ /^(SLES.+)-Build(\d+\.\d+)\.vhd$/;
        $img_by_group->{$prefix} //= [];
        push(@{$img_by_group->{$prefix}}, { name => $name, build => $build,  creationTime => str2time($i->{properties}->{creationTime}), delete_me => 0});
    }
    for my $key (keys %{$img_by_group}){
        my @sorted_data = sort {$a->{build} cmp $b->{build}} @{$img_by_group->{$key}};
        for(my $i = 0; $i < @sorted_data; $i++){

            # Mark all older images to be deleted
            $sorted_data[$i]->{delete_me} = 1 if ($i < @sorted_data - $keep_img);
            $sorted_data[$i]->{delete_me} = 1 if ($sorted_data[$i]->{creationTime} < time() - 3600 * 24 * 30);

            # Store images in return hash
            $ret->{$sorted_data[$i]->{name}} = $sorted_data[$i];
        }
        $img_by_group->{$key} = \@sorted_data;
    }
    return $ret;
}

my $data = decode_json(run("az storage blob list --account-name $storage_acc --container-name $storage_container"));
my $images = annotate_images($data);

while (my ($name, $img) = each %{$images}) {
    next if ($img->{delete_me} != 1);
    print ("DELETE : " . $name . $/);
    run("az storage blob delete --account-name $storage_acc --container-name $storage_container --name " . $name);
}
while (my ($name, $img) = each %{$images}) {
    next if ($img->{delete_me} != 0);
    print ("KEEP : " . $name . $/);
}

$data = decode_json(run("az resource list --resource-group $rgroup"));
for my $d (@{$data}){
    next if (!exists($images->{$d->{name}}) || $images->{$d->{name}}->{delete_me} != 1);
    if ($d->{'type'} eq 'Microsoft.Compute/images'){
        run("az image delete --resource-group '$rgroup' --name '". $d->{name} . "'");
    } elsif ($d->{type} eq 'Microsoft.Compute/disks' ) {
        run("az disk delete --resource-group '$rgroup' --name '". $d->{name} . "' -y");
    }
}
