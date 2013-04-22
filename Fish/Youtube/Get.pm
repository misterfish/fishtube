#!/usr/bin/perl

package Fish::Youtube::Get;

use Moose;

use 5.10.0;

use Term::ANSIColor;
use Data::Dumper 'Dumper';

use HTTP::Cookies;
use LWP::UserAgent;
use URI::Escape qw/ uri_unescape uri_escape /;
use HTML::Entities qw/ decode_entities encode_entities /;
use IO::File;

use File::stat;

use AnyEvent::HTTP;

use Fish::Youtube::Utility;

#use POSIX ':sys_wait_h';

$SIG{INT} = $SIG{KILL} = sub { exit(1) };

my $DEFAULT_TMP = '/tmp';

has status => (
    is  => 'ro',
    isa => 'Str',
    writer => 'set_status',
);

has _c => (
    is => 'rw',
    isa => 'Str',
);

has _cancel => (
    is => 'rw',
    isa => "Bool",
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

# opt_f means try to continue, and otherwise overwrite.
# Note that if the file has been fully downloaded it will be left alone,
# even with force.

has force => (
    is  => 'ro',
    isa => 'Bool',
    default => 0,
);

has mode => (
    is => 'ro',
    isa => 'Str',
    default => 'standalone',
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

# wait for user to call set
has no_init_params => (
    is  => 'ro',
    isa => 'Bool',
);

has _efh => (
    is  => 'rw',
    isa => 'IO::File',
);

my @QUALITY = qw/ small medium large hd720 hd1080 /;

my $DEFAULT_QUALITY = 'medium';
my $DEFAULT_TYPE = 'x-flv';

has _movie_url => (
    is  => 'rw',
    isa => 'Str',
);

has error => (
    is  => 'rw',
    isa => 'Bool',
    writer => 'set_error',
);

has errstr => (
    is => 'rw',
    isa => 'Str',
    writer => 'set_errstr',
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
    (-d $tmp and -w $tmp) or $self->err("Invalid tmp:", R $tmp), return;

    my $ef = "$tmp/yt-err";
    my $fh = IO::File->new(">$ef") or $self->err("Can't open error file", Y $ef, R $!), return;
    $self->_efh($fh);
    $fh->autoflush(1);

    my $Out_file;

    my $ua = LWP::UserAgent->new;
    $self->ua($ua);

    $ua->agent('Mozilla/5.0 (X11; Linux i686; rv:10.0.5) Gecko/20100101 Firefox/10.0.5 Iceweasel/10.0.5');

    # necessary?
    my $cookie_jar = HTTP::Cookies->new(
        file     => $tmp . "/yt-cook-$$",
        autosave => 1,
    );
    $ua->cookie_jar( $cookie_jar );

    # hang forever
    $ua->timeout(0);

    my $res = $self->ua->get($self->url);

    if (!$res->is_success) {
        my $s = $res->status_line;
        my $t = $s ? ": " . Y $s : '.';
        $self->err($t);
        return;
    }

    # can be partial content ... apparently still timing out sometimes?

    # can take some time
    $self->d2('getting metadata.');

# Test error
#$self->err('blah!'); while (1) { sleep 1;

    my $c = $res->decoded_content;

    $self->_c($c);
    $self->d2('got metadata.');

    my $data = $self->extract_urls(\$c);
    if (!$data) {
        $self->err("Couldn't get avail.");
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

    # no init params is used in prompt mode.
    if (! $self->no_init_params ) {
        $self->_set_params;
        $self->set($self->quality, $self->type);
    }
}

sub set {
    my ($self, $quality, $type) = @_;
    if (my $d = $self->avail_by_quality->{$quality}{$type}) {
        my $u = $d->[1];
        $self->_movie_url($u);
    }
    else {
        $self->err("Invalid quality and type", Y $quality, B $type);
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

    return 1;
}

sub get_start {
    my ($self, $done_r, $cancel_r) = @_;

    return $self->get_size(sub {
        my ($size) = @_;

        $self->size($size);
        $self->set_status('started');

        $self->get_go($done_r, $cancel_r);
    });
}

# in eventloop case, return 1 if it seems to be going ok.
# otherwise return the size.
sub get_size {
    # cb only for eventloop mode
    my ($self, $cb) = @_;

    $self->error and warn, return;
    my $url = $self->_movie_url;
    $url or warn, return;

    my $cl;

    if ($self->mode eq 'eventloop') {
        http_head $url, sub {
            my ($data, $headers_r) = @_;

            #for (keys %$headers_r) { D $_, $headers_r->{$_}; }

            $cl = $headers_r->{'content-length'};

            #D 'got size', $cl;

            return unless $self->headers_ok($headers_r) and $cl;

            $cb or warn, return;
            $cb->($cl);
        };

        return 1;
    }
    else {
        my $ua = $self->ua;

        my $u_sub = substr($url, 0, 20) . "...";

        $ua->add_handler( response_header => sub {
            my ( $res, $ua, $h ) = @_;
            $cl = $res->header('content-length');
        });

        # get 1 byte
        $ua->max_size(1);

        $ua->get($url);

        $self->d2('got cl', $cl);

        return $cl;
    }

}

# main wrapper for get.
sub get {
    # cancel_r allows cancel while downloading
    my ($self, $done_r, $cancel_r) = @_;

    $self->error and warn, return;

    if ($self->mode eq 'eventloop') {
        # chains to get_go
        return $self->get_start($done_r, $cancel_r);
    }
    else {
        my $size = $self->get_size or warn, return;

        $self->size($size);
        $self->set_status('started');

        return $self->get_go($done_r, $cancel_r);
    }
}

sub get_go {

    my ($self, $done_r, $cancel_r) = @_;

    my $of = $self->out_file or warn, return;

    my %request_hdr;
    my $resume;
    my $seek = 0;

    my $size = $self->size or warn, return;

    if (-e $of) {

        my $cur_size = -s $of;

        if ($self->force) {
            if ($cur_size == $size) {
                D2 'nothing to do!';
                $self->set_status('done');
                return 1;
            }

            if ($self->mode eq 'eventloop') {
                # try to resume, otherwise overwrite.
                my $s = stat $of;
                if (my $size = $s->size) {
                    $resume = 1;
                    $seek = $size;
                    $request_hdr{"if-unmodified-since"} = AnyEvent::HTTP::format_date($s->mtime);
                    $request_hdr{"range"} = "bytes=$size-";
                }
            }
            else {
                # overwrite
            }
        }
        else {
            my $pwd = sys_chomp 'pwd';
            if ($of !~ /^\//) {
                $of = "$pwd/$of";
            }
            utf8::encode($of);
            $self->err(Y $of, "exists");
            return;
        }
    }
    sys qq, touch "$of" ,;

    # will die on error, has been checked above
    my $fh = safeopen ">$of";

    $self->error and warn, return;

    my $url = $self->_movie_url;
    if (!$url) {
        warn;
        return;
    }

    $self->d2('url', $url);
    if ($self->mode eq 'eventloop') {
        # Uses glib mainloop for 'async' get.

        http_get $url, 
        
            headers => \%request_hdr,

            on_header => sub {
                my ($hdr) = @_;
                my $status = $hdr->{Status};
                if ($resume and $status == 200) {
                    # resume failed, should be 2xx
                    truncate $fh, 0;
                    # last 0 means abs
                    sysseek $fh, 0, 0;
                }
                # err will get caught anyway
                else {
                    # last 0 means abs
                    $seek != 0 and D2 'seeking to', $seek;
                    sysseek $fh, $seek, 0;
                }
            },

            on_body => sub {
                my ($buf, $headers_r) = @_;

                if ($self->_cancel) {
                    $self->d('cancelled.');
                    $self->set_status('cancelled');
                    return;
                }

                return unless $self->headers_ok($headers_r);

                syswrite $fh, $buf or do {
                    my ($space, $part) = free_space $of;
                    if ($space == 0) {
                        $self->err("No more free space on partition '$part'");
                    }
                    else {
                        $self->err("Can't write to filehandle though disk is not full.");

                    }
                    return;
                };

                1;
            }, sub {
                my ($body, $headers_r) = @_;

                return if $self->_cancel;

                return unless $self->headers_ok($headers_r);
                # all done, no body here.
                $self->set_status('done');
            }
        ;
    }
    else {
        my @callback = (':content_cb' => sub { 
            my ($chunk, $res, $protocol) = @_;

            if ($self->_cancel) {
                $self->d('cancelled.');
                $self->set_status('cancelled');
                return;
            }

            syswrite $fh, $chunk;
        });

        my $ua = $self->ua;
        $self->ua->max_size(undef);

        my $res = $ua->get($url,
            #':content_file'     => $of,
            @callback,
        );

        if (!$res->is_success) {
            $self->err("Can't get movie:", Y $res->status_line );
            return;
        }

        $self->set_status('done');
    }

    return 1;
}

# destroy XX
sub cancel {
    my ($self) = @_;
    $self->_cancel(1);
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
            $self->err("Couldn't find url_encoded_fmt_stream_map in content.");
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
                $vars{$_} or $self->err( "Couldn't find ", G $_, " in u: ", $u);
            }

            $vars{url} .= "&signature=$vars{sig}";

            my $u = $vars{url} or $self->err("Can't find URL"), return;
            my $q = $vars{quality} or $self->err("Can't find quality"), return;
            my $t = $vars{type} or $self->err("Can't find type"), return;

            $self->d2('type', $t);
            $self->d2('qual', $q);

            $ret{$q}{$t} = $u;

            # check here later for more formats.
            next;
        }
        elsif ($u =~ / url /x) {
            $self->err( "Not implemented: url");
        }
        else {
            $self->err( R "Didn't find", G 'itag', R 'or', G 'url', R 'in', G 'u:', BB $u);
        }
    }

    return \%ret;
}

sub types { @TYPES }
sub qualities { @QUALITY }

1;

sub END {
}

# warn to stdout, write to errfile if present, and store in errstr and set
# error flag.
sub err {
    my ($self, @s) = @_;
    my $s = join ' ', @s, "\n";
    warn $s;
    if (my $fh = $self->_efh) {
        say $fh $s;
    }
    $self->set_error(1);
    $self->set_errstr($s);
    $self->set_status('error');
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
            $self->err("Can't get preferred type", Y $pt, "and not tolerant.");
            return;
        }

    }

    if (not $q) {
        if (! $self->is_tolerant_about_quality) {
            $self->err("Can't get preferred quality", Y $pq, "and not tolerant.");
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
        $self->err( "Setting unrecognised type:", Y $ty);
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
        $self->err( "Setting unrecognised quality:", Y $qu);
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
            $self->err( "No known qualities.");
            my $qu = (keys %$abq)[0];
            $self->err( "Setting unrecognised quality:", Y $qu);
            $self->_set_quality($qu);
            $d = $abq->{$qu};
        }

        my $e;

        for my $t (@TYPES) {
            $e = $d->{$t} or next;
            $self->_set_type($t);
            return 1;
        }

        $self->err( "No known types.");
        my $ty = (keys %$abt)[0];
        $self->err( "Setting unrecognised quality:", Y $ty);
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

sub headers_ok {
    my ($self, $headers_r) = @_;

    my $status = $headers_r->{Status};
    if ($status !~ /^2/) {
        my $t = $self->errstr || sprintf "%s (status %s)", $headers_r->{Reason}, $headers_r->{Status};
        $self->err($t);

        return;
    }

    return 1;
}




__END__

