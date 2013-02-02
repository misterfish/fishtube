package Fish::Youtube::Test;

use 5.10.0;

use threads;
use threads::shared;
use Thread::Queue;

my $III = 0;

my $NUM_THREADS = 4;
my $Terminate :shared = 0;
our $Queue_idle = Thread::Queue->new;

# signals ...

our %Queues_work;

for (1 .. $NUM_THREADS) {
    my $q = Thread::Queue->new;
    my $thr = async { thread($q) };
    $Queues_work{$thr->tid} = $q;
}

sub thread {
    my $q = shift;
    my $tid = threads->tid;
    while (1) {
        last if $Terminate;

        $Queue_idle->enqueue($tid);
        my $ir = $q->dequeue;


        last if $sub == -1;
    }
    say "$tid done.";
}
1;
