use Mojo::Base 'base';
use Mojo::JSON qw(decode_json encode_json);
use Date::Parse;
use Mojo::File 'path';

my $out = `az storage blob list --account-name openqa --container-name sle-images`;
#my $out = path('data.cache')->slurp();
die("list blob failed") if ($?);

my $data = decode_json($out);

my @sorted_data = sort {str2time($a->{properties}->{creationTime}) cmp str2time($b->{properties}->{creationTime})} @{$data};
for(my $i = 0; $i < @sorted_data - 3; $i++){
    my $img = $sorted_data[$i];
    print "DELETE : ";
    print $img->{properties}->{creationTime};
    print " ";
    print $img->{name};
    print $/;
    system("az storage blob delete --account-name openqa --container-name sle-images --name " . $img->{name});
}

for(my $i = @sorted_data - 3; $i < @sorted_data; $i++){
    my $img = $sorted_data[$i];
    print "KEEP: ";
    print $img->{properties}->{creationTime};
    print " ";
    print $img->{name};
    print $/;
}


