package SSHBackend;
use Expect;
use Mojo::Base -base;

has ['prompt', 'linux_prompt'] => '\r?\n[^:]+:~\s*(#|>)';
has my_prompt => 'MY_UNIQUE_PROMPT_(\d+)_#\s+';
has my_ps1    => 'MY_UNIQUE_PROMPT_$?_# ';
has e         => undef;

sub connect
{
    my ($self, $host, $username, $password) = @_;

    my @params;
    if (-f $password) {
        push(@params, "-i", $password);
    }
    push(@params, $username . "@" . $host);
    my $exp = Expect->spawn("ssh", @params);

    die("unable to spawn ssh") unless $exp;

    $self->e($exp);

    # Connect to host;
    $exp->expect(60,
        [qr/\(yes\/no\)\?/ => sub {
                my $exp = shift;
                $exp->send("yes\n");
                exp_continue;
            }
        ],
        [qr/(P|p)assword:\s*/ => sub {
                my $exp = shift;
                $exp->send($password . "\n");
                exp_continue;
            }
        ],
        eof =>
          sub {
            die "ERROR: login failed ssh quit!\nssh " . join(" ", @params);
          },
        [$self->linux_prompt => sub {
                my $exp = shift;
                print "Login successful" . $/;
            }
        ]
    );

    # Change to root
    if ($username ne "root") {
        $self->e->send("sudo su\n");
        $self->expect_prompt(5);
    }

    # change prompt
    $exp->send("PS1='" . $self->my_ps1 . "'\n");
    $self->prompt($self->my_prompt);
    die("unable to set PROMPT") unless $self->expect_prompt == 0;
}

sub run_cmd
{
    my ($self, $cmd, $timeout) = @_;
    $timeout //= 60;
    $self->e->clear_accum();
    $self->e->send($cmd . "\n");
    $self->e->expect(10, "-re", $cmd . "\r?\n");
    return $self->expect_prompt($timeout);
}

sub run_assert
{
    my ($self, $cmd, $timeout) = @_;

    my ($ret, $out) = $self->run_cmd($cmd, $timeout);
    die("[TIMEOUT] on cmd '$cmd'") unless (defined($ret));
    die("[ERROR] on cmd '$cmd'")   unless ($ret == 0);
    wantarray ? ($ret, $out) : $ret;
}

sub expect_prompt
{
    my ($self, $timeout) = @_;
    my $retval;
    $timeout //= 60;
    if ($self->e->expect($timeout, '-re', $self->prompt)) {
        if ($self->e->match() =~ $self->prompt) {
            $retval = $1;
        }
    }

    wantarray ? ($retval, $self->e->before()) : $retval;
}

1;
