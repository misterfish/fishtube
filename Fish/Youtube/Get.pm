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

has _c => (
    is => 'rw',
    isa => 'Str',
);

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

has avail_by_quality => (
    is => 'rw',
    isa => 'HashRef',
);

has avail_by_type => (
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

has preferred_quality => (
    is  => 'ro',
    isa => 'Str',
    default => 'medium',
);

has is_tolerant_about_quality => (
    is => 'ro',
    isa => 'Bool',
    default => 1,
);

has preferred_type => (
    is  => 'ro',
    isa => 'Str',
    default => 'mp4',
);

has is_tolerant_about_type => (
    is => 'ro',
    isa => 'Bool',
    default => 1,
);

has quality => (
    is  => 'ro',
    isa => 'Str',
    writer => '_set_quality',
);

has type => (
    is  => 'ro',
    isa => 'Str',
    writer => '_set_type',
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
    defined $self->quality and die "don't set quality";
    defined $self->type and die "don't set type";

    $self->preferred_type('x-flv') if $self->preferred_type eq 'flv';

    my $tmp = $self->tmp;
    (-d $tmp and -w $tmp) or war("Invalid tmp:", R $tmp), return;

    my $Out_file;

    my $ua = LWP::UserAgent->new;
    $self->ua($ua);

    $ua->agent('Mozilla/5.0 (X11; Linux i686; rv:10.0.5) Gecko/20100101 Firefox/10.0.5 Iceweasel/10.0.5');

    # necessary?
    my $cookie_jar = HTTP::Cookies->new(
        file     => $self->tmp . "/yt-cook-$$.txt",
        autosave => 1,
    );
    $ua->cookie_jar( $cookie_jar );

    # hang forever
    $ua->timeout(0);

    my $YT_FILE = ".yt-file";
    $Yt_file = $self->tmp . "/$YT_FILE-$$";

    my $res = $self->ua->get($self->url);

    if (!$res->is_success) {
        war "Can't get avail:", Y $res->status_line ;
        return;
    }

    # can be partial content ... apparently still timing out sometimes?

    my $c = $res->decoded_content;
    $self->_c($c);

    my $data = $self->extract_urls(\$c);
    if (!$data) {
        war "Couldn't get avail.";
        return;
    }
    $self->d2('data', $data);

    my %abq = ();
    my %abt = ();

    for my $q (keys %$data) {
        my $d = $data->{$q};
        for my $t (keys %$d) {
            my $url = $d->{$t};
            my ($short_type) = ($t =~ /video \/ ([^;]+)/x);

            $abq{$q}{$short_type} = [$t, $url];
            $abt{$short_type}{$q} = [$t, $url];
        }
    }

    $self->avail_by_quality(\%abq);
    $self->avail_by_type(\%abt);

    my ($quality, $type) = $self->_set_params;
    
    $self->set($self->quality, $self->type);
}

sub set {
    my ($self, $quality, $type) = @_;
    if (my $d = $self->avail_by_quality->{$quality}{$type}) {
        my $u = $d->[1];
        $self->_movie_url($u);
    }
    else {
        war "Invalid quality and type", Y $quality, B $type;
        return 0;
    }

    my $of = $self->out_file;

    if ( ! $of ) {
        my $title = ($self->_c =~ m|<title>(.+?)</title>|si)[0];
        $title =~ s/ *-\s*youtube\s*$//gi;

        $title =~ s/^\s+//;
        $title =~ s/\s+$//;

        $title = decode_entities $title;

        $title =~ s/[\n:!\*<>\`\$]//g;

        $title =~ s|/ |-|gx;
        $title =~ s|\\|-|g;
        $title =~ s/"/'/g;

        my $ext = $type;
        $ext = 'flv' if $ext eq 'x-flv';
        $self->d2('ext', $ext);
        $of = $title . ".$ext";
    }

    my $dir = $self->dir;
    # rel -- put dir
    if ($dir and $of !~ /^\//) {
        $of = $dir . "/" . $of;
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
        warn;
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
        warn;
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
sub qualities { @QUALITY }

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

sub _set_params {
    my ($self) = @_;
    my $abq = $self->avail_by_quality;
    my $abt = $self->avail_by_type;

    %$abq or warn, return;
    %$abt or warn, return;

    my $pq = $self->preferred_quality;
    my $pt = $self->preferred_type;

    my $q;
    my $t;

    if (my $d = $abq->{$pq}) {
        $self->_set_quality($pq);
        $q = $pq;

        if ($d->{$pt}) {
            $self->_set_type($pt);
            $t = $pt;
        }
    }

    elsif (my $e = $abt->{$pt}) {
        $self->_set_type($pt);
        $t = $pt;

        if ($e->{$pq}) {
            $self->_set_quality($pq);
            $q = $pq;
        }
    }

    if ($q and $t) { 
        return 1;
    }

    if (not $t) {
        if (! $self->is_tolerant_about_type) {
            war "Can't get preferred type", Y $pt, "and not tolerant.";
            return;
        }

    }

    if (not $q) {
        if (! $self->is_tolerant_about_quality) {
            war "Can't get preferred quality", Y $pq, "and not tolerant.";
            return;
        }
    }

    if ($q) {
        my @t = rotate(\@TYPES, $pt);
        my $d = $abq->{$q};

        for my $t (@t) {
            if ($d->{$t}) {
                $self->_set_type($t);
                return 1;
            }
        }

        # panic -- unknown type
        my $ty = (keys %$d)[0];
        warn "Setting unrecognised type:", Y $ty;
        $self->_set_type($ty);
        return 1;
    }
    elsif ($t) {
        my @q = rotate(\@QUALITY, $pq);
        my $d = $abt->{$t};
        for my $q (@q) {
            if ($d->{$q}) {
                $self->_set_quality($q);
                return 1;
            }
        }

        # panic -- unknown qual
        my $qu = (keys %$d)[0];
        warn "Setting unrecognised quality:", Y $qu;
        $self->_set_quality($qu);
        return 1;
    }
    elsif (not $q and not $t) {
        my $d;
        for my $q (@QUALITY) {
            $d = $abq->{$q} or next;
            $self->_set_quality($q);
            last;
        }
        if (!$d) {
            warn "No known qualities.";
            my $qu = (keys %$abq)[0];
            warn "Setting unrecognised quality:", Y $qu;
            $self->_set_quality($qu);
            $d = $abq->{$qu};
        }

        my $e;

        for my $t (@TYPES) {
            $e = $d->{$t} or next;
            $self->_set_type($t);
            return 1;
        }

        warn "No known types.";
        my $ty = (keys %$abt)[0];
        warn "Setting unrecognised quality:", Y $ty;
        $self->_set_type($ty);
        return 1;
    }
}

sub rotate {
    my ($list, $start) = @_;
    my @list = @$list;
    my $i = -1;
    my (@l, @r);
    if ($start ~~ $list) {
        for (@list) {
            $i++;
            if ($_ eq $start) {
                @r = splice @list, 0, $i;
                shift @list;
                @l = @list;
                return (@l, @r);
            }
        }
    }
    else {
        return @$list;
    }
}

sub check {
    my ($self, $p_qual, $p_type) = @_;
    $p_type = 'x-flv' if $p_type eq 'flv';
    my ($quality, $type);
    if (my $d = $self->avail->{$p_qual}) {
        $quality = $p_qual;
        for my $t (keys %$d) {
            D2 'type', $t;
            if ($t =~ /video\/$p_type/) {
                D2 'got preferred type', $t;

                $type = $t;

                last;
            }
        }
    }
    return ($quality, $type);
}


__END__

