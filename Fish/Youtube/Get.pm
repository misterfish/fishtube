#!/usr/bin/perl

package Fish::Youtube::Get;

use Moose;

use 5.10.0;

use threads;
use threads::shared;

use Term::ANSIColor;
use Data::Dumper 'Dumper';
use Time::HiRes 'sleep';
use HTTP::Cookies;
use LWP::UserAgent;
use URI::Escape qw/ uri_unescape uri_escape /;
use Getopt::Std;
use HTML::Entities qw/ decode_entities encode_entities /;
use File::stat;
use Fish::Youtube::Utility;

#use POSIX ':sys_wait_h';

sub error;
sub war;

$SIG{INT} = $SIG{KILL} = sub { exit(1) };

my $DEFAULT_TMP = '/tmp';

#my $Content_length :shared = undef;
#my $Outfile_size :shared = 0;
#my $Yt_file :shared;
my $Content_length = undef;
my $Outfile_size = 0;
my $Yt_file;

has immediate_fork => (
    is  => 'ro',
    isa => 'Bool',
    default => 0,
);

# optional, determined from title if missing
has out_file => (
    is  => 'ro',
    isa => 'Str',
);

has debug => (
    is  => 'ro',
    isa => 'Bool',
    default => 0,
);

has force => (
    is  => 'ro',
    isa => 'Bool',
    default => 0,
);

# optional, defaults to cur dir
has dir => (
    is  => 'ro',
    isa => 'Str',
);

has tmp => (
    is  => 'rw',
    isa => 'Str',
    default => $DEFAULT_TMP;
);

has avail => (
    is => 'rw',
    isa => 'HashRef',
);

has url => (
    is  => 'ro',
    isa => 'Str',
    required => 1,
);

has ua => (
    is  => 'rw',
    isa => 'LWP::UserAgent',
);

# get something based on preferred_xxx

has immediate_fork => (
    is  => 'ro',
    isa => 'Bool',
    default => 0,
);

my @QUALITY = qw/ small medium large hd720 hd1080 /;
has preferred_quality => (
    is  => 'ro',
    isa => 'Str',
    default => 'small',
);

my @QUALITY_ORDER = qw/ asc desc /;
has preferred_quality_order => (
    is  => 'ro',
    isa => 'Str',
    default => 'asc';
);

# flv / mp4
my @TYPES = qw/ flv mp4 /;
has preferred_type => (
    is  => 'ro',
    isa => 'Str',
    default => 'mp4',
);

sub d2 {
    my ($self, @d) = @_;
    $self->debug and D @d;
}

sub BUILD {
    my ($self, $args) = @_;

    my $Out_file;

    my $ua = LWP::UserAgent->new;
    $self->ua($ua);

    if ($self->immediate_fork) {
        $self->preferred_quality ~~ [@QUALITY] or error "Invalid quality.";
        $self->preferred_quality_order ~~ [@QUALITY_ORDER] or error "Invalid quality order.";
        $self->preferred_type ~~ [@TYPES] or error "Invalid type.";
    }

    $ua->agent('Mozilla/5.0 (X11; Linux i686; rv:10.0.5) Gecko/20100101 Firefox/10.0.5 Iceweasel/10.0.5');

    my $cookie_jar = HTTP::Cookies->new(
        file     => "$Tmp/yt-cook.txt",
        autosave => 1,
    );
    $ua->cookie_jar( $cookie_jar );

    # hang forever
    $ua->timeout(0);

    my $YT_FILE = ".yt-file";
    $Yt_file = "$Tmp/$YT_FILE-$$";

    my $quiet = $self->quiet;
    $quiet or D 'url', $Url;
}

sub get_metadata {
    my ($self) = @_;
    my $res = $ua->get($self->url);

    local $Fish::Youtube::LOG_LEVEL = 2 if $self->debug;

    $res->is_success or die $res->status_line ;

    # can be partial content ... apparently still timing out sometimes?

    my $c = $res->decoded_content;
    my $of = $self->out_file;

    my $quiet = $self->quiet;

    if ( ! $of ) {
        my $title = ($c =~ m|<title>(.+?)</title>|si)[0];
        $title =~ s/ *-\s*youtube\s*$//gi;

        $title =~ s/^\s+//;
        $title =~ s/\s+$//;

        $title = decode_entities $title;

        $title =~ s/[\n:!\*<>\`\$]//g;

        $title =~ s|/ |-|gx;
        $title =~ s|\\|-|g;
        $title =~ s/"/'/g;

        $quiet or D 'title', $title;

        $of = $title . ".flv";
    }

    my $dir = $self->dir;
    # rel -- put dir
    if ($dir and $of !~ /^\//) {
        $of .= $dir . "/$Out_file";
    }

    $self->of($of);

    $quiet or D 'pid yg', $$;
    $quiet or D 'out file', $of;

    if (-e $of and ! $self->force) {
        my $pwd = sys_chomp 'pwd';
        if ($of !~ /^\//) {
            $of = "$pwd/$of";
        }
        utf8::encode($of);
        error Y $of, "exists, exiting.";
    }
    sys qq, touch "$of" ,;

    my $data = extract_urls(\$c);
    $self->d2('data', $data);

    $self->avail($data);

    return $data;
}

sub get {
    my ($self, $quality, $type) = @_;
    local $Fish::Youtube::LOG_LEVEL = 2 if $self->debug;

    my $url = $self->data{$quality}{$type};

    if (!$url) {
        warn "Couldn't get preferred url based on qual/type; using first.";
        die;
        #$url = $self->data{
    }

    my $u_sub = substr($url, 0, 20) . "...";

    $self->d2('url', $url);
    $self->d2('Out_file', $Out_file);

    $self->ua->add_handler( response_header => sub {
        my ( $res, $ua, $h ) = @_;
        $Content_length = $res->header('content-length');
    });

    my @range = ();

    $self->d2('url', $url);

    my $res = $ua->get($url,
        ':content_file'     => $of,
    );

}

sub extract_urls {
    my $c_r = shift;
    my $c = $$c_r;

    #$url = $ret{$qual}{$size} 
    my %ret = (
    );

    my @urls;

    {
        # copied from flash downloader extension
        $c =~ /"url_encoded_fmt_stream_map": "([^"]*)"/;
        my $u = $1;
        if (!$u) {
            D 'Failed content', $c;
            error "Couldn't find url_encoded_fmt_stream_map in content.";
        }

        @urls = split /,/, $_u;
    }

    for my $u (@urls) {
        $u = uri_unescape $u;
        $self->d2('u', $u);
        if ($u =~ / itag= /x) {
            my %vars;
            my @fields = split /\\u0026/, $u;
            for (@fields) {
                /^(.+?)=(.+)$/ or next;
                $vars{$1} = $2;
            }

            for (qw/ url itag type fallback_host sig quality / ) {
                $vars{$_} or warn "Couldn't find ", G $_, " in u: ", $u;
            }

            $vars{url} .= "&signature=$vars{sig}";

            my $u = $vars{url} or war ("Can't find URL"), return;
            my $q = $vars{quality} or war ("Can't find quality"), return;
            my $t = $vars{type} or war ("Can't find type"), return;

            $self->d2('type', $t);
            $self->d2('qual', $q);

            $ret{$q}{$t} = $u;

            # check here later for more formats.
            next;
        }
        #elsif ($u =~ /^ url /x) {
        elsif ($u =~ / url /x) {
            warn "Not implemented: url";
        }
        else {
            warn R "Didn't find", G 'itag', R 'or', G 'url', R 'in', G 'u:', BB $u;
        }
    }

    return \%ret;
}

    sub metadata_file {
        while (1) {
            # set in main thread
            defined $Out_file and last;
            $self->d2('waiting for out_file');
            sleep .5;
        }
        $self->d2('got out', $Out_file);
        my $o = $Out_file;
        utf8::decode $o;
        while (1) {
            # set in main thread
            defined $Content_length and last;
            $self->d2('waiting for content_length');
            sleep .5;
        }
        $self->d2('got cl', $Content_length);
        open my $fh, ">:utf8", "$Yt_file" or die "$Yt_file: $!";

        say $fh $o;
        say $fh $Content_length;

        $self->d2('printed to out', $Yt_file);
    }

    ## resumes if necessary (in contrast to ->get)
    # doesn't do what i thought.
    #$res = $ua->mirror($url, $o);

    if ( ! $res->is_success ) {
        warn sprintf "error with url (%s): %s", $u_sub, $res->status_line;
    }

    say STDERR '';

}

sub progress {
    my $first = 1;
    while ( 1 ) {
        $first ? $first = 0 : sleep .5 ;
        if (!$Content_length) {
            sleep .5;
            next;
        }

        my $offset = $Outfile_size || 0;
        my $a = nice_bytes (stat($Out_file)->size);
        my $b = nice_bytes ($Content_length + $offset);

        my $s = sprintf "%s / %s", B $a, B $b;

        print STDERR "\r" . " " x 40 . "" x 40;
        printf STDERR $s;
    }
}

sub END {
#    if ($Yt_file) {
#        open my $fh, ">:utf8", "$Yt_file" or die "$Yt_file: $!";
#        say $fh ($Ok ? "$Out_file\n$Content_length" : '');
#    }
}



sub error {
    my @s = @_;
    die join ' ', @s, "\n";
}

sub war {
    my @s = @_;
    warn join ' ', @s, "\n";
}


__END__

    if($outfile_exists) {
        $Outfile_size = (stat $Out_file)->size;
    #    my $start = (stat $Out_file)->size;
    #    $start++;
    my $start = 171226943;
        $opt_q or say "Resuming from ", G $start, " bytes";
    $o .= 'resume';

    $url .= "&range=$start-";

    #TWO PROBLEMS:
    #clobbers the file, and is unreadable as movie, probably because you have to
    #go left a bit or right a bit.
    #maybe give params to url?
        #@range = (':range' => "bytes=$start-");
    }


    $M == DETACH and $meta_thread->join;
    my $meta_thread = async { metadata_file() };

    #$quiet or threads->create(\&progress)->detach;
