package Fish::Youtube::DownloadThreads;

use strict;
use warnings;

use 5.10.0;

use threads;
use threads::shared;
use Thread::Queue;

use Carp;


#use Gtk2 qw/ -init -threads-init /;

use Fish::Youtube::Get;
use Fish::Youtube::Gtk;
use Fish::Youtube::Utility;

my $NUM_THREADS = 4;
my $Terminate :shared = 0;
our $Queue_idle = Thread::Queue->new;

# signals ...

my @QUALITY = Fish::Youtube::Get->qualities;
my @TYPES = Fish::Youtube::Get->types;

our %Queues_in;
our %Queues_out;

#our %Metadata_by_tid :shared;
our %Metadata_by_did :shared;
our %Status_by_did :shared;
our %Cancel_by_did :shared;

# D2 doesn't work (log_level set in wrong 'copy')

for (1 .. $NUM_THREADS) {
    my $qi = Thread::Queue->new;
    my $qo = Thread::Queue->new;

    my $thr = async { thread($qi, $qo) };

    my $tid = $thr->tid;
    $Queues_in{$tid} = $qi;
    $Queues_out{$tid} = $qo;
}

sub _die {
    my ($q, @s) = @_;
    my %m = (
        error => 1,
    );
    $m{errstr} = join ' ', @s if @s;
    warn 'blach';
    # segfaults!
    #Carp::cluck();

    eval { 
        Carp::confess();
    };

    warn $@;
    $q->enqueue(\%m);
}

sub thread {
    my ($qi, $qo) = @_;

    my $tid = threads->tid;
    while (1) {
        last if $Terminate;

        $Queue_idle->enqueue($tid);

        # Go.

        my $msg = $qi->dequeue;
        
        # download id
        my $did = $msg->{did};
        defined $did or warn, _die($qo);

        {
            my %s :shared = ( status => 'init' );
            $Status_by_did{$did} = \%s;
        }

        my $err;

        # Can't use 'die', causes segfaults (probably because queue is still
        # hanging on the other side).
       
        my $url = $msg->{url} or warn, _die($qo);

        # as text, not id
        my $prefq = $msg->{prefq};
        defined $prefq or warn, _die($qo);
        my $preft = $msg->{preft};
        defined $preft or warn, _die($qo);

        # is_tolerant
        my $itaq = $msg->{itaq};
        defined $itaq or warn, _die($qo);
        my $itat = $msg->{itat};
        defined $itat or warn, _die($qo);

        # if prefq and preft are both known, then we are in async mode. 
        my $async = $msg->{async};
        defined $async or warn, _die($qo);

        D 'threads: async is', $async;

        my %md :shared = (
            size => undef,
            of => undef,
        );

        $Metadata_by_did{$did} = \%md;

        my @p;
        if (! $async) {
            my $output_dir = $msg->{output_dir} or warn, _die($qo);
            @p = (
                dir => $output_dir,
                no_init_params => 1,
            );
        }
        else {
            @p = (
                preferred_qual => $prefq,
                preferred_type => $preft,
                is_tolerant_about_quality => $itaq,
                is_tolerant_about_type => $itat,
            );
        };

        my @init = (
            dir => '/tmp',
            url => $url,

            # gui should take care of prompting for overwrite
            force => 1,

            @p,
        );

        my $get = Fish::Youtube::Get->new(@init);

        if ($get->error) {
            $qo->enqueue({error => 'error building get object'});

            D "couldn't build the object";

            $Status_by_did{$did}->{status} = 'error';
            $Status_by_did{$did}->{errstr} = $get->errstr;

            next;
        }

        # ready to download. if any prompts are cancelled, it will stay idle
        # forever.
        $Status_by_did{$did}->{status} = 'idle';

        my $set_ok;
        if ($async) {
            # caller stops listening to us after this.
            # get object figures out what it needs to do, ->set not
            # necessary.
            $qo->enqueue({ async => 1});

            # if he hasn't signalled ->error (above), then he was able to
            # find a qual and type.
            $set_ok = 1;
        }
        else {

            # enqueue undef as cheap way to signal err
            
            my $abq = $get->avail_by_quality or warn, $qo->enqueue(undef), next;
            my $abt = $get->avail_by_type or warn, $qo->enqueue(undef), next;

            my @quals = map { defined $abq->{$_} ? $_ : () } @QUALITY;

            my $response;

            $qo->enqueue( { quals => \@quals } );

            $response = $qi->dequeue or warn, next;

            next if $response->{cancel};

            my $qual = $response->{qual} or warn, next;

            my $types = $abq->{$qual} or warn, next;

            my @types = keys %$types;

            $qo->enqueue( { types => \@types } );

            # chosen type
            my $response2 = $qi->dequeue or warn, next;

            next if $response2->{cancel};

            my $type = $response2->{type};

            #D "Ok, getting", 'qual', $qual, 'type', $type;

            $set_ok = $get->set($qual, $type);
        }

        my $size = $get->get_size;
        my $of = $get->out_file;

        # will be undef if ! set_ok 
        $md{size} = $size;
        $md{of} = $of;

        # if async, not possible (or annoyingly hard) to check if output
        # file exists. so just overwrite. (->force is set above).

        if (!$async) {
            $qo->enqueue( $set_ok ? { got_metadata => 1 } : { error => 1 } );

            my $response3 = $qi->dequeue or warn, next;

            next if $response3->{cancel};

            $response3->{go} or warn, next;
        }

        $Status_by_did{$did}->{status} = $set_ok ? 'getting' : 'error';

        # No more queueing. Communicate through md and status.

        my $ok = $get->get(\$Cancel_by_did{$did});

        if ($Cancel_by_did{$did}) {
            $Status_by_did{$did}->{status} = 'cancelled';
        }
        elsif ($ok) {
            $Status_by_did{$did}->{status} = 'done';
        } else {
            $Status_by_did{$did}->{status} = 'error';
            $Status_by_did{$did}->{errstr} = $get->errstr;
        }
    }
    D2 "cleanup -- $tid done.";
}


sub queue_idle { $Queue_idle }
sub queues_in { \%Queues_in }
sub queues_out { \%Queues_out }
1;
