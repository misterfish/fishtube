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

our %Metadata_by_tid :shared;
our %Is_getting :shared;

for (1 .. $NUM_THREADS) {
    my $qi = Thread::Queue->new;
    my $qo = Thread::Queue->new;

    my $thr = async { thread($qi, $qo) };

    my $tid = $thr->tid;
    $Queues_in{$tid} = $qi;
    $Queues_out{$tid} = $qo;

    my %md :shared = (
        size => -1,
        of => undef,
        #err => 0,
    );

    $Metadata_by_tid{$tid} = \%md;
    $Is_getting{$tid} = 0;
}

#our $Metadata_by_tid = shared_clone \%_metadata_by_tid;

our %Temp :shared;

sub thread {
    my ($qi, $qo) = @_;

    my $tid = threads->tid;
    while (1) {
        last if $Terminate;

        my $md = $Metadata_by_tid{$tid};
        $md->{size} = -1;
        $md->{of} = undef;
        #$md->{err} = 0;
        $Is_getting{$tid} = 0;

        $Queue_idle->enqueue($tid);

        my $msg = $qi->dequeue;
        
        my $err;

        my $url = $msg->{url} or warn, $err = 1;
        my $prefq = $msg->{prefq};
        defined $prefq or warn, $err = 1;
        my $preft = $msg->{preft};
        defined $preft or warn, $err = 1;
        # is_tolerant
        my $itaq = $msg->{itaq};
        defined $itaq or warn, $err = 1;
        my $itat = $msg->{itat};
        defined $itat or warn, $err = 1;

        my $error_file = $msg->{error_file} or warn, $err = 1;

        if ($err) {
            warn 'init error';
            $qo->enqueue({err => 1});
            next;
        }

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

        D @init;
        my $get = Fish::Youtube::Get->new(@init);

        if ($get->error) {
            warn "error building get object.";
            $qo->enqueue({err => 1});
            next;
        }

    # from here on, don't send {err => 1} objects

    if ($async) {
    }
    else {

        my $abq = $get->avail_by_quality or warn, $qo->enqueue(undef), next;
        my $abt = $get->avail_by_type or warn, $qo->enqueue(undef), next;

        my @quals = map { defined $abq->{$_} ? $_ : () } @QUALITY;

        my $response;

        $qo->enqueue( { quals => \@quals } );

        # cancelled
        $response = $qi->dequeue or next;

        my $qual = $response->{qual};

        my $types = $abq->{$qual} or next;

        my @types = keys %$types;

        $qo->enqueue( { types => \@types } );

        my $response2 = $qi->dequeue;

        if (!%$response2) {
            say "Ok, cancelling";
            next;
        }

        my $type = $response2->{type};

        D "Ok, getting", 'qual', $qual, 'type', $type;

        $get->set($qual, $type);

    }

        my $size = $get->get_size;
        my $of = $get->out_file;

        D 'storing md for tid', $tid;

        $md->{size} = $size;
        $md->{of} = $of;

        $Temp{$tid} = $size;

        #if (-r $of) {
        #    my $ok = Fish::Youtube::Gtk::replace_file_dialog($of);
        #
        #    return unless $ok;
        #}

        D 'downloading', 'size', $size;

        # set to 1 after md set.
        $Is_getting{$tid} = 1;

        my $ok = $get->get;
        if ($ok) {
            D 'ok!';
        } else {
            D 'error with download';
            $Is_getting{$tid} = 0;
        }
    }
    say "$tid done.";
}


sub queue_idle { $Queue_idle }
sub queues_in { \%Queues_in }
sub queues_out { \%Queues_out }
1;
