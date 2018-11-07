#!/usr/bin/perl

use strict;
use warnings;
use Data::Dumper;
use Mojo::JSON qw(decode_json encode_json);
use Getopt::Long;


sub all_jobs_finished {
    my ($ids) = @_;

    for my $id (@{$ids}) {
        my $m = eval (`/usr/share/openqa/script/client jobs/$id`);
        if ($m->{job}->{state} ne 'done'){
            return 0;
        }
    }
    return 1;
}

my $script = undef;
GetOptions(
    "script=s" => \$script
);

die("Missing --script") unless($script);
die("File not found") unless -f $script;
die("File not executable") unless -x $script;

my $cnt = 0;
my $err = {jobs => {}};
while(1) {
    print("#"x79 . $/);
    print("# Run: $cnt$/");
    $cnt = $cnt + 1;
    my $out = `$script`;
    my $o = eval($out);
    if ($@){
        die($@);
    }

    while(!all_jobs_finished($o->{ids})) {
            sleep 5;
    }

    for my $id (@{$o->{ids}}) {
        $out = `/usr/share/openqa/script/client jobs/$id`;
        my $m = eval($out);

        my $res = $m->{job}->{result};
        print "State: " . $m->{job}->{state} . " Result:" . $res . $/;
        if (exists($err->{$res})){
            $err->{$res} = $err->{$res}+1;
        } else {
            $err->{$res} = 1;
        }
        $err->{jobs}->{$res} //= [];
        push(@{$err->{jobs}->{$res}}, $id);
    }
    print Dumper($err);
}
