#!/usr/bin/perl

package Fish::Youtube::Get;

use Moose;

use 5.10.0;

#use threads;
#use threads::shared;

use Term::ANSIColor;
use Data::Dumper 'Dumper';

use HTTP::Cookies;
use LWP::UserAgent;
use URI::Escape qw/ uri_unescape uri_escape /;
use HTML::Entities qw/ decode_entities encode_entities /;

use Fish::Youtube::Utility;

#use POSIX ':sys_wait_h';

sub war;

$SIG{INT} = $SIG{KILL} = sub { exit(1) };

my $DEFAULT_TMP = '/tmp';

#my $Content_length :shared = undef;
#my $Outfile_size :shared = 0;
#my $Yt_file :shared;
my $Content_length = undef;
my $Outfile_size = 0;
my $Yt_file;

# optional, determined from title if missing
has out_file => (
    is  => 'rw',
    isa => 'Str',
);

has size => (
    is => 'rw',
    isa => 'Num',
);

has debug => (
    is  => 'ro',
    isa => 'Bool',
    default => 0,
);

has quiet => (
    is  => 'ro',
    isa => 'Bool',
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
    default => $DEFAULT_TMP,
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

my @QUALITY = qw/ small medium large hd720 hd1080 /;

my $DEFAULT_QUALITY = 'medium';
my $DEFAULT_TYPE = 'x-flv';

has _movie_url => (
    is  => 'rw',
    isa => 'Str',
);

# x-flv / mp4 / webm / 3gpp / [others?]
my @TYPES = qw/ mp4 x-flv webm 3gpp /;

sub d2 {
    my ($self, @d) = @_;
    $self->debug and D @d;
}

sub BUILD {
    my ($self, $args) = @_;

    defined $self->size and die "don't set size";

    my $Out_file;

    my $ua = LWP::UserAgent->new;
    $self->ua($ua);

    $ua->agent('Mozilla/5.0 (X11; Linux i686; rv:10.0.5) Gecko/20100101 Firefox/10.0.5 Iceweasel/10.0.5');

    my $cookie_jar = HTTP::Cookies->new(
        file     => $self->tmp . "/yt-cook.txt",
        autosave => 1,
    );
    $ua->cookie_jar( $cookie_jar );

    # hang forever
    $ua->timeout(0);

    my $YT_FILE = ".yt-file";
    $Yt_file = $self->tmp . "/$YT_FILE-$$";
}

sub get_avail {
    my ($self) = @_;
    my $res = $self->ua->get($self->url);

    if (!$res->is_success) {
        war "Can't get avail:", Y $res->status_line ;
        return;
    }

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
        $of .= $dir . "/" . $self->out_file;
    }

    $self->out_file($of);

    if (-e $of and ! $self->force) {
        my $pwd = sys_chomp 'pwd';
        if ($of !~ /^\//) {
            $of = "$pwd/$of";
        }
        utf8::encode($of);
        war Y $of, "exists";
        return;
    }
    sys qq, touch "$of" ,;

    my $data = $self->extract_urls(\$c);
    if (!$data) {
        war "Couldn't get avail.";
        return;
    }
    $self->d2('data', $data);

    $self->avail($data);

    return $data;
}

sub set {
    my ($self, $quality, $type) = @_;
    #$self->_quality($quality);
    #$self->_type($type);
    if (my $u = $self->avail->{$quality}{$type}) {
        $self->_movie_url($u);
    }
    else {
        war "Invalid quality and type", Y $quality, B $type;
        return 0;
    }
    return 1;
}

sub set_defaults {
    my ($self) = @_;
    return $self->set($DEFAULT_QUALITY, $DEFAULT_TMP);
}

sub get_size {
    my ($self) = @_;
    my $url = $self->_movie_url;
    if (!$url) {
        war "First call set() or set_defaults()";
        return;
    }

    my $ua = $self->ua;

    my $u_sub = substr($url, 0, 20) . "...";

    my $cl;
    $ua->add_handler( response_header => sub {
        my ( $res, $ua, $h ) = @_;
        $cl = $res->header('content-length');
    });

    $ua->max_size(1);
    $ua->get($url);

    $self->d2('got cl', $cl);

    return $cl;
}

sub get {
    my ($self) = @_;

    my $url = $self->_movie_url;
    if (!$url) {
        war "First call set() or set_defaults()";
        return;
    }

    my $ua = $self->ua;

    my $u_sub = substr($url, 0, 20) . "...";

    my $of = $self->out_file;

    #$self->d2('url', $url);
    #$self->d2('Out_file', $of);

#my @range = ();

    $self->d2('url', $url);

    $ua->max_size(undef);
    my $res = $ua->get($url,
        ':content_file'     => $of,
    );
}

sub extract_urls {
    my ($self, $c_r) = @_;
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
            war "Couldn't find url_encoded_fmt_stream_map in content.";
            return;
        }

        @urls = split /,/, $u;
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
        elsif ($u =~ / url /x) {
            warn "Not implemented: url";
        }
        else {
            warn R "Didn't find", G 'itag', R 'or', G 'url', R 'in', G 'u:', BB $u;
        }
    }

    return \%ret;
}

sub types { @TYPES }
sub quality { @QUALITY }

1;

sub END {
#    if ($Yt_file) {
#        open my $fh, ">:utf8", "$Yt_file" or die "$Yt_file: $!";
#        say $fh ($Ok ? "$Out_file\n$Content_length" : '');
#    }
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

    ## resumes if necessary (in contrast to ->get)
    # doesn't do what i thought.
    #$res = $ua->mirror($url, $o);


