#!/usr/bin/perl -w

use strict;
use warnings;
use Getopt::Long;
use Pod::Usage qw(pod2usage);

use lib '.';
use SSHBackend;


sub number_of_cpus
{
    my ($ctx) = @_;

    my ($ret, $out) = $ctx->{backend}->run_assert("getconf _NPROCESSORS_ONLN");

    $out =~ s/^\s+//;
    $out =~ s/\s+$//;
    return $out;
}

sub write_log {
    my ($ctx, $name, $retvalue, $output) = @_;
    open(my $fh, '>>', $ctx->{'log-file'})
      or die("FAILED OPEN FILE " . $ctx->{'log-file'});
    my $res = 'FAILED';
    if ($retvalue == 0) {
        $res = 'SUCCESSFUL';
    }
    elsif ($retvalue == 32) {
        $res = 'NOT_SUPPORTED';
    }
    print $fh sprintf("TEST: %20s %s$/", $name, $res);
    close($fh);

    open(my $fh2, '>>', $ctx->{'output-file'})
      or die("FAILED OPEN FILE " . $ctx->{'output-file'});
    print $fh2 $/ . $/;
    print $fh2 "#" x 79 . $/;
    print $fh2 "# $name " . $/;
    print $fh2 "#" x 79 . $/;
    print $fh2 $output;
    close($fh2);
}

sub run_ltp {
    my ($ctx, $ltp_file, $exclude) = @_;

    my ($ret, $output) = $ctx->{backend}->run_assert('cat ' . $ltp_file);
    my $ltp_bin = '/opt/ltp/testcases/bin';

    for my $fname (($ctx->{'output-file'}, $ctx->{'log-file'})) {
        open(my $fh2, '>>', $fname)
          or die("FAILED OPEN FILE " . $fname);
        print $fh2 $/ . $/;
        print $fh2 "#" x 79 . $/;
        print $fh2 "# $ltp_file " . $/;
        print $fh2 "#" x 79 . $/;
        close($fh2);
    }

    $ctx->{backend}->run_assert("cd $ltp_bin");

    for my $l (split(/\r?\n/, $output)) {
        next if ($l =~ /^#|^$/);

        if ($l =~ /^\s*([\w-]+)\s+(.+)$/) {
            my $name = $1;
            my $cmd  = $2;
            if ($name !~ m/$exclude/) {
                my ($ret, $tout) = $ctx->{backend}->run_cmd("./" . $cmd, 60 * 30);
                die("TIMEOUT on $cmd") unless defined($ret);
                write_log($ctx, $name, $ret, $tout);
            }
        }
    }
    $ctx->{backend}->run_assert("cd - ");
}


MAIN:
{
    my $ctx = {
        SCC_REGKEY       => undef,
        HOST             => undef,
        USERNAME         => undef,
        PASSWORD         => undef,
        'log-file'       => "ltp_log.txt",
        'output-file'    => "ltp_out.txt"
    };
    my $help = 0;
    my $man  = 0;

    GetOptions(
        "host=s"        => \$ctx->{host},
        "scc-regkey=s"  => \$ctx->{'scc-regkey'},
        "username=s"    => \$ctx->{username},
        "password=s"    => \$ctx->{password},
        "log-file=s"    => \$ctx->{'log-file'},
        "output-file=s" => \$ctx->{'output-file'},
        "help"          => \$help,
        "man"           => \$man
    );

    pod2usage(1) if $help;
    pod2usage(-verbose => 2) if $man;

    for my $mandatory (qw(scc-regkey username password host)) {
        pod2usage("Missing mandatory paramter --$mandatory") unless $ctx->{$mandatory};
    }

    my $backend = SSHBackend->new;
    $backend->connect($ctx->{host}, $ctx->{username}, $ctx->{password});
    $ctx->{'backend'} = $backend;

    $backend->run_assert("cd");
    $backend->run_assert("pwd");

    $backend->run_assert("sudo SUSEConnect -r " . $ctx->{'scc-regkey'});

    my ($ret, $output) = $backend->run_assert("SUSEConnect -l");
    $output =~ s/\x1b\[[0-9;]*[a-zA-Z]//gm;
    if ($output =~ /(SUSEConnect (-d\s+)?-p sle-sdk\/[\d\.]+\/x86_64)/) {
        if ($2) {
            print("Module already activated!$/");
        } else {
            $backend->run_assert($1);
        }
    } else {
        die("Missing sdk module!");
    }


    my @deps = qw(
      autoconf
      automake
      bison
      expect
      flex
      gcc
      git-core
      kernel-default-devel
      keyutils-devel
      libacl-devel
      libaio-devel
      libcap-devel
      libopenssl-devel
      libselinux-devel
      libtirpc-devel
      libnuma-devel
      make
    );

    $backend->run_assert("sudo zypper -n in " . join(' ', @deps));

    if ($backend->run_cmd("test -d ltp") != 0) {
        $backend->run_assert('git clone --depth 1 https://github.com/linux-test-project/ltp');
    }

    $backend->run_assert('cd ltp');
    $backend->run_assert('git log -1 --pretty=format:"git-%h" | tee /opt/ltp_version');

    $backend->run_assert('make autotools');
    $backend->run_assert('./configure --with-open-posix-testsuite --with-realtime-testsuite', 60 * 5);
    $backend->run_assert('make -j' . number_of_cpus($ctx), 60 * 10);
    $backend->run_assert('export CREATE_ENTRIES=1');
    $backend->run_assert('make install', 60 * 3);


    $backend->run_assert('export PATH=/opt/ltp/testcases/bin:$PATH');
    $backend->run_assert('export LTPROOT=/opt/ltp');
    $backend->run_assert('export TMPBASE=/tmp');
    $backend->run_assert('export TMPDIR=/tmp');

    for my $fname (($ctx->{output_file_name}, $ctx->{log_file_name})) {
        unlink $fname if (-f $fname);
    }

    my $exclude_regex_syscalls = '_16$|^(move_pages|msg(ctl|get|rcv|snd|stress)|sem(ctl|get|op|snd)|shm(at|ctl|dt|get)|fanotify07|syslog|inotify07|inotify08)';
    my $exclude_regex_cve      = "cve-2015-3290";
    if (number_of_cpus($ctx) == 1) {
        $exclude_regex_syscalls .= "|inotify09";
        $exclude_regex_cve      .= "|cve-2014-0196|cve-2016-7117|cve-2017-2671";
    }

    run_ltp($ctx, '/opt/ltp/runtest/syscalls', $exclude_regex_syscalls);

    run_ltp($ctx, '/opt/ltp/runtest/cve', $exclude_regex_cve);
}

__END__

=head1 NAME

run_ltp.pl - Script to run LTP on a publiccloud instance connecting via SSH

=head1 SYNOPSIS

run_ltp.pl [options]

=head1 OPTIONS

=over 4

=item B<--help>

Print a brief help message and exits.

=item B<--man>

Print the manual page and exists.

=item B<--host>

Specify the hostname to connect to (required).

=item B<--scc-regkey>

Specify the scc registration code used for registration.

=item B<--username>

Set the username used for ssh connection

=item B<--password>

Set the password or the ssh-key to use for authentication.

=item B<--log-file>

Specify the log output filename (default: ltp_lot.txt). If file exists, it will be overwritten.

=item B<--output-file>

Specify the LTP output filename (default: ltp_out.txt). If file exists, it will be overwritten.

=back

=head1 DESCRIPTION

Helper script to install and run LTP (syscalls and cve) on a publiccloud instance. 
The connection is done via SSH. The output is written to logfiles.

=cut
