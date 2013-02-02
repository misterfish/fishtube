package Fish::Youtube::Test;

use strict;
use warnings;

use 5.10.0;

use threads;
use threads::shared;
use Thread::Queue;

use Fish::Youtube::Get;
use Fish::Youtube::Utility;

my $NUM_THREADS = 4;
my $Terminate :shared = 0;
our $Queue_idle = Thread::Queue->new;

# signals ...

my @QUALITY = Fish::Youtube::Get->quality;
my @TYPES = Fish::Youtube::Get->types;

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

        my $get = Fish::Youtube::Get->new(
            dir => '/tmp',
            url => $url,
        );

        $get->get_avail;
        my $avail = $get->avail;

        #my $p_qual = 'medium';
        #my $p_type = 'mp4';
        #my ($quality, $type) = $get->check($p_qual, $p_type);
        #if ($quality) {
        #    D 'Got preferred quality but not type.';
        #    $type = $get->fallback($p_type, $p_qual, $quality);
        #}
        #else {
        #    D "Getting fallback quality and type.";
        #    ($quality, $type) = $get->fallback($p_type, $p_qual);
        #}

        #$qr->enqueue([$quality, $type]);
        my @sort = map { defined $avail->{$_} ? $_ : () } @QUALITY;
        $qr->enqueue(\@sort);

        my $response = $qw->dequeue;

        my $size = $response->{size};

        my $types = $avail->{$size};

        #my @sort2 = map { defined $types->{$_} ? $_ : () } @TYPES;
        my @types = keys %$types;

        $qr->enqueue(\@types);

        my $response2 = $qw->dequeue;

        if (!%$response2) {
            say "Ok, cancelling";
            next;
        }

        my $type = $response2->{type};

        D "Ok, getting", 'size', $size, 'type', $type;

        #last unless %$msg;
    }
    say "$tid done.";
}


sub queue_idle { $Queue_idle }
sub queues_work { \%Queues_work }
sub queues_response { \%Queues_response }
1;
