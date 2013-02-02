package Fish::Youtube::Test;

use strict;
use warnings;

use 5.10.0;

use threads;
use threads::shared;
use Thread::Queue;

my $III = 0;

my $NUM_THREADS = 4;
my $Terminate :shared = 0;
our $Queue_idle = Thread::Queue->new;

# signals ...

my %T = (
    a => [qw/ small medium large/],
    b => ['small'],
);

my $T = shared_clone \%T;

our %Queues_work;
our %Queues_response;

for (1 .. $NUM_THREADS) {
    my $qw = Thread::Queue->new;
    my $qr = Thread::Queue->new;

    my $thr = async { thread($qw, $qr) };

    $Queues_work{$thr->tid} = $qw;
    $Queues_response{$thr->tid} = $qr;
}

sub thread {
    my ($qw, $qr) = @_;
    my $tid = threads->tid;
    while (1) {
        last if $Terminate;

        $Queue_idle->enqueue($tid);
        my $msg = $qw->dequeue;
        
        my $url = $msg->{url};

        my @options = @{$T->{$url}};
        say "Thread $tid, options are ", join ' ', @options;

        $qr->enqueue(\@options);

        my $response = $qw->dequeue;

        if (!%$response) {
            say "Ok, cancelling";
        }
        else {
            say "Ok, getting $response->{size}";
        }

        last if $msg == {};
    }
    say "$tid done.";
}


sub queue_idle { $Queue_idle }
sub queues_work { \%Queues_work }
sub queues_response { \%Queues_response }
1;
