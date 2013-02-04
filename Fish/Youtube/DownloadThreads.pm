package Fish::Youtube::DownloadThreads;

use strict;
use warnings;

use 5.10.0;

use threads;
use threads::shared;
use Thread::Queue;

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

for (1 .. $NUM_THREADS) {
    my $qi = Thread::Queue->new;
    my $qo = Thread::Queue->new;

    my $thr = async { thread($qi, $qo) };

    my $tid = $thr->tid;
    $Queues_in{$tid} = $qi;
    $Queues_out{$tid} = $qo;

    #my %md :shared = (
    #    size => undef,
    #    of => undef,
    #    #err => 0,
    #);

    #$Metadata_by_tid{$tid} = \%md;
}

sub thread {
    my ($qi, $qo) = @_;

    my $tid = threads->tid;
    while (1) {
        last if $Terminate;

        $Queue_idle->enqueue($tid);

        my $msg = $qi->dequeue;
        
        my $err;

        # download id
        my $did = $msg->{did} // die;

        my $url = $msg->{url} // die;

        my $prefq = $msg->{prefq} // die;
        my $preft = $msg->{preft} // die;

        # is_tolerant
        my $itaq = $msg->{itaq} // die;
        my $itat = $msg->{itat} // die;

        my $error_file = $msg->{error_file} // die;

        {
            my %s :shared = ( status => 'init' );
            $Status_by_did{$did} = \%s;
        }

        my %md :shared = (
            size => undef,
            of => undef,
        );

        $Metadata_by_did{$did} = \%md;

        my $async = 1;
        $async = 0 unless $preft and $prefq;

        my @p;
        if (! $async) {
            @p = ( no_init_params => 1 );
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
            error_file => $error_file,
            url => $url,

            # gui should take care of prompting for overwrite
            #force => 1,

            @p,
        );

        my $get = Fish::Youtube::Get->new(@init);

        if ($get->error) {
            $qo->enqueue({error => 'error building get object'});

            $Status_by_did{$did}->{status} = 'error';
            $Status_by_did{$did}->{errstr} = $get->errstr;

            next;
        }

        # ready to download. if any prompts are cancelled, it will stay idle
        # forever.
        $Status_by_did{$did}->{status} = 'idle';

        my $set_ok;
        if ($async) {
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

            if (!%$response2) {
                next;
            }

            my $type = $response2->{type};

            D2 "Ok, getting", 'qual', $qual, 'type', $type;

            $set_ok = $get->set($qual, $type);
        }

        my $size = $get->get_size;
        my $of = $get->out_file;

        #D 'storing md for tid', $tid;
        #DC 'set ok', $set_ok, 'of', $of, 'size', $size;

        # will be undef if set_ok not 1
        $md{size} = $size;
        $md{of} = $of;

        #if (-r $of) {
        #    my $ok = Fish::Youtube::Gtk::replace_file_dialog($of);
        #
        #    return unless $ok;
        #}

        $Status_by_did{$did}->{status} = $set_ok ? 'getting' : 'error';

        #D 'returning', $set_ok ? 'ready' : 'error';

        $qo->enqueue( $set_ok ? { ready => 1 } : { error => 1 } );

        #D 'downloading', 'size', $size;

        # No more queueing. Communicate through md and status.

        # give chance to cancel here  XX

        my $ok = $get->get;
        if ($ok) {
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
