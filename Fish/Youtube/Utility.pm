package Fish::Youtube::Utility;

use 5.10.0;

BEGIN {
    use Exporter ();
    @ISA = qw/Exporter/;
    @EXPORT_OK = qw/
        d
        mywait round 
        get_date get_date_2 
        sayf RESETR
        bench_start bench_end bench_end_pr bench_pr
        remove_quoted_strings
            error
    /;

    @EXPORT = qw/
        sys sys_chomp sys_ok sysl sysll 
        safeopen sys_return_code datadump
        debug_level info_level verbose_cmds
            war warl info ask
        e8 d8

        is_defined def 
        unshiftr pushr shiftr popr scalarr keysr eachr
        contains containsr
        chompp rl
        list hash 

        disable_colors force_colors
        R BR G BG B BB CY BCY Y BY M BM RESET ANSI GREY
        D D2 D3 D_QUIET D_RAW D2_RAW DC DC_QUIET

        slurp slurp8 slurpn slurpn8 
        cat strip strip_ptr 

        cross check_mark yes_no 

        set_debug

        randint is_int is_even is_odd is_num
        field pad nice_bytes nice_bytes_join comma

        datestring datestring2 get_file_no

    /;
}

use 5.14.0;

use strict;
use warnings;

use utf8;

use List::Util 'first';
use Term::ANSIColor;
use Carp 'confess';
use Data::Dumper;

# for bench
use Time::HiRes 'time';

our $Cmd_verbose = 0;
our $Debug_level = 0;
our $Info_level = 1;

our $Disable_colors = 0;
our $Force_colors = 0;

our $Check = '✔';
our $Cross = '✘';

sub D;
sub D2;
sub D3;
sub D_QUIET;

sub d8;
sub e8;

sub error;
sub war;
sub info;

sub safeopen;
sub list;

# - - - 
sub set_debug {
    warn "set_debug deprecated";
    debug_level(@_);
}

sub set_info_level {
    warn "set_info_level deprecated";
    info_level(@_);
}

sub set_verbose { 
    warn "set_verbose deprecated";
    verbose_cmds(@_);
}
# - - - 

sub verbose_cmds {
    shift if $_[0] eq __PACKAGE__;
    $Cmd_verbose = shift if @_;
    $Cmd_verbose;
}

sub info_level {
    shift if $_[0] eq __PACKAGE__;
    $Info_level = shift if @_;
    $Info_level;
}

sub debug_level {
    shift if $_[0] eq __PACKAGE__;
    $Debug_level = shift if @_;
    $Debug_level;
}

# ; means optional.

# bright is either bold or a bit lighter.
sub R (;$)          { return _color('red', @_) }
sub BR (;$)         { return _color('bright_red', @_) }
sub G (;$)          { return _color('green', @_) }
sub BG (;$)         { return _color('bright_green', @_) }
sub B (;$)          { return _color('blue', @_) }
sub BB (;$)         { return _color('bright_blue', @_) }
sub CY (;$)         { return _color('cyan', @_) }
sub BCY (;$)         { return _color('bright_cyan', @_) }
sub Y (;$)          { return _color('yellow', @_) }
sub BY (;$)          { return _color('bright_yellow', @_) }
sub M (;$)          { return _color('magenta', @_) }

sub cross { $Cross }
sub check_mark { $Check }

# actually the same as magenta.
sub BM (;$)          { return _color('bright_magenta', @_) }

# 0 .. 15
sub ANSI ($;$)   { my $a = shift; return _color("ansi$a", @_) }
# 0 .. 23
sub GREY ($;$)   { my $a = shift; return _color("grey$a", @_) }

sub RESET           { return _color('reset') }

sub disable_colors { 
    $Disable_colors = 1;
    $Force_colors = 0;
}

sub force_colors {
    $Force_colors = 1;
    $Disable_colors = 0;
}

sub sys_chomp {
    my ($ret, $code) = sys(@_);
    # catch more than chomp
    $ret =~ s/ \s* $//x;
    return wantarray ? ($ret, $code) : $ret;
}

# Two ways to call: 
# ($command, $die, $verbose)
# ($command, { die => , verbose =>, list => }

# returns $out in list ctxt
# returns ($out, $code) in list ctxt (if die is 0)
# returns $out in list ctxt (if die is 1)

sub sys {
    my ($command, $arg2, $arg3) = @_;

    my ($die, $verbose);

    my $opt;

    strip_ptr(\$command);

    if ( $arg2 and ref $arg2 eq 'HASH' ) {
        $opt = $arg2;
        $die = $opt->{die};
        $verbose = $opt->{verbose};
    }
    else {
        $die = $arg2;
        $verbose = $arg3;
        $opt = {};
    }

    $die //= 1;
    $verbose //= $Cmd_verbose;

    my $wants_list = $opt->{list} // 0;
    my $kill_err = $opt->{killerr} // 0;
    my $utf8 = $opt->{utf8} || $opt->{UTF8} || $opt->{'utf-8'} || $opt->{'UTF-8'} // 0;
    my $quiet = $opt->{quiet} // 0;

    my @out;
    my $out;
    my $ret;
    my $err;

    my $ctxt_list = wantarray && ! $die;

    my $c = remove_quoted_strings($command);

    $kill_err and $command = "$command 2>/dev/null";

    # &
    if ( ($c =~ /\s+\&\s+/) || ($c =~ /\s+\&$/)) {
        say "Executing (no return value):\n$command" if $verbose;
        system("$command");
        $out = "[cmd immediately bg'ed, output not available]";
    } 
    else {
        say sprintf "%s %s", G '*', $command if $verbose;
        if ($wants_list) {
            @out = map { 
                chomp; $utf8 ? d8 $_ : $_
            } `$command`;
        } else {
            $out = `$command`;
            utf8::encode $out if $utf8;
        }
        $ret = $?;
        $err = $!;
    }

    if ($ret) {
        my $e = $err ? 
            sprintf "Couldn't execute cmd %s: %s", BR $command, BR $err :
            sprintf "Couldn't execute cmd %s.", BR $command;
        if ($die) {
            error $quiet ? $err : $e;
        }
        elsif (! $quiet) {
            war $e;
        }
    }

    # perl thing
    $ret >>= 8 if defined $ret and $ret > 0;

    if ($wants_list) {
        return $ctxt_list ? (\@out, $ret, $err) : \@out;
    } else {
        return $ctxt_list ? ( $out, $ret, $err ) : $out;
    }
}

sub sys2 {
    my $command = shift;
    `$command`;
    return $?;
}

sub sysl {
    my ($command, $arg1, $arg2) = @_;
    return ref $arg1 eq 'HASH' ? 
        sys $command, { list => 1, %$arg1 } : 
        sys($command, {
            die => $arg1,
            verbose => $arg2,
            list => 1,
        })
    ;
}

sub sysll {
    list scalar sysl @_;
}

sub sys_return_code {
    my ($command, @args) = @_;
    # don't die
    if (ref $args[0] eq 'HASH') {
        $args[0]->{die} = 0;
    }
    else {
        $args[0] = 0;
    }
    my (undef, $ret) = sys $command, @args;
    return $ret;
}

sub sys_ok {
    my ($command, @args) = @_;
    my $opt = ref $args[0] eq 'HASH' ? shift @args : {};
    $opt->{quiet} = 1;
    return ! sys_return_code($command, $opt, @args);
}

sub mywait {
    my $proc_name = shift;
    my $cmd = qq/ps -C "$proc_name"/;

    my $return;

    while (! ($return = sys2($cmd))) {
        print qq/Still waiting for "$proc_name" to hang up./;
        sleep 1;
    }

}

sub get_date {
    my $date = localtime(time);
    $date =~ s/[: ]/_/g;
    return $date;
}


# 12345 -> 12,345
sub comma($) {
    my $n = shift;
    my @n = reverse split //, $n;
    my @ret;
    while (@n > 3) {
        my @m = splice @n, 0, 3;
        push @ret, @m, ',';
    }
    push @ret, @n;
    join '', reverse @ret;
}



sub round {
    my $s = shift;
    my ($s_int, $s_frac) = ( int ($s), $s - int ($s) );
    if ($s_frac >= .5) {
        return $s_int + 1;
    } else {
        return $s_int;
    }
}

# Shouldn't use this for opening commands: difficult or impossible to get
# error messages when the command exists but fails (e.g. find
# /non/existent/path)

sub safeopen {
    (scalar @_ < 3) || error("safeopen() called incorrectly");

    my $file = shift;

    my $die;
    my $is_dir;

    my $arg2 = shift;

    my $utf8;
    my $quiet;
    if (ref $arg2 eq 'HASH') {
        # require an arg to open dirs, to avoid mistakes.
        $die = $arg2->{die};
        $is_dir = $arg2->{dir};
        $utf8 = $arg2->{utf8} || $arg2->{UTF8} || $arg2->{'utf-8'} || $arg2->{'UTF-8'};
        $quiet = $arg2->{quiet} // 0;
    }
    # old form
    else {
        $die = $arg2;
    }

    $die //= 1;

    if ( -d $file ) {
        if (! $is_dir) {
            war "Deprecated -- need opt 'dir => 1' to use safeopen with a dir.";
            exit 1;
        }
        if ( opendir my $fh, $file ) {
            return $fh;
        }
        else {
            $die and error "Couldn't open directory", R $file, "--", R $!;
            return undef;
        }
    }

    my $op = 
        $file =~ />/ ? 'writing' :
        $file =~ />>/ ? 'appending' :
        $file =~ /\|\s*$/ ? 'pipe reading' :
        $file =~ /^\s*\|/ ? 'pipe writing' :
        'reading';

    if ( open my $fh, $file ) {
        binmode $fh, ':utf8' if $utf8;
        # In the case of a command, could still be an error.
        return $fh;
    } 
    else {
        my @e = ("Couldn't open filehandle to", R $file, "for", Y $op, "--", R $!);
        $die and error @e;
        war @e unless $quiet;
        return undef;
    }
}

sub datestring {
    my $time = shift;
    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = 
        localtime($time); 
    my @months = qw/ Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec /;
    my $month = $months[$mon];
    $year = 1900 + $year;
    return sprintf ("%s %02d, %d %02d:%02d:%02d", $month, $mday, $year, $hour,
        $min, $sec);
}

sub datestring2 { get_date_2(@_) }

sub error {
    my @s = @_;
    die R '* ', join ' ', @s, "\n";
}

# war { opts => }, str1, str2, ...
# or war str1, str2, ...
# same for info.
sub war {
    my ($opts, $string) = _process_print_opts(@_);

    _disable_colors_temp(1) if $opts->{disable_colors};

    utf8::encode $string;
    warn BR '* ', $string, "\n";

    _disable_colors_temp(0) if $opts->{disable_colors};
}

# A version of war which is guaranteed to return an empty list.
sub warl {
    war(@_);
    ();
}

# warn with stack trace
# doesn't pipe through war()
sub wartrace {
    my $w = join ' ', BR '*', @_;
    utf8::encode $w;
    Carp::cluck($w);
}

sub info {
    return unless $Info_level;
    my ($opts, $string) = _process_print_opts(@_);

    _disable_colors_temp(1) if $opts->{disable_colors};

    utf8::encode $string;
    say BB '* ', $string;

    _disable_colors_temp(0) if $opts->{disable_colors};
}

sub ask {
    return unless $Info_level;
    my @s = @_;
    local $\ = undef;
    print M '* ', (join ' ', @s), '? ';
}

# common opt processing for info, war, etc.
sub _process_print_opts {
    my ($string, $opts);
    $opts = ref $_[0] eq 'HASH' ? shift : {};
    my @s;
    for (@_) {
        push @s, ref eq 'ARRAY' ? 
            ( @$_ ? join '|', @$_ : '[empty]' ) :
            $_;
    }
    return $opts, join ' ', @s;
}

# 1 -> disable colors, storing value of state
# 0 -> restore
sub _disable_colors_temp {
    my ($s) = @_;
    state $dc;
    if ($s) {
        $dc = $Disable_colors;
        disable_colors(1);
    }
    else {
        disable_colors($dc);
        $dc = undef;
    }
}

sub strip_ptr {
    my $ptr = shift;
    $$ptr = strip($$ptr);
}

sub strip {
    no warnings;
    
    my $a = shift;
    $a =~ s/^\s+//;
    $a =~ s/\s+$//;
    return $a;
}

sub yes_no {
    if (! -t STDOUT) {
        D "\nyes_no: STDOUT not connected to tty, assuming no.";
        return 0;
    }
    if (! -t STDIN) {
        D "\nyes_no: STDIN not connected to tty, assuming no.";
        return 0;
    }
    my $opt = shift || {};
    if (ref $opt eq '') {
        $opt = 
            $opt eq 'yes' ? { default_yes => 1 } :
            $opt eq 'no'  ? { default_no  => 1 } :
            (warn, return);
    }
    my $infinite = $opt->{infinite} // 1;
    my $default_yes = $opt->{default_yes} // 0;
    my $default_no = $opt->{default_no} // 0;

    if (my $d = $opt->{default}) {
        $d eq 'no' ?  $default_no = 1 :
        $d eq 'yes' ? $default_yes = 1 :
        war ("Unknown 'default' opt given to yes_no()");
    }
    my $question = $opt->{question} // $opt->{ask} // '';
    $default_no and $default_yes and warn, return;
    my $y = $default_yes ? 'Y' : 'y';
    my $n = $default_no ? 'N' : 'n';
    ask "$question" if $question;
    my $print = "($y/$n) ";
    local $\ = undef;
    while (1) {
        printf "$print";
        my $in = <STDIN>;
        strip_ptr(\$in);
        if (!$in) {
            if ($default_yes) {
                return 1;
            } 
            elsif ($default_no) {
                return 0;
            }
        }
        elsif ($in =~ /^y$/i) {
            return 1;
        }
        elsif ($in =~ /^n$/i) {
            return 0;
        }

        if ( ! $infinite) {
            return 0;
        }
    }
}

sub get_date_2 {
    my $time = shift // time;
    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime($time);

    return sprintf("%d-%02d-%02d-%02d.%02d.%02d", $year+1900, $mon+1, $mday, $hour, $min, $sec);
}

sub datadump {
    return Data::Dumper->Dump([shift]);
}

# inclusive
sub randint {
    my ($low, $high) = @_;
    return (int rand ($high + 1 - $low) + $low);
}

sub sayf {
    # idiosyncrasy with sprintf; doesn't like sprintf(@_)
    say sprintf shift, @_;
}
        
sub d {
    return Dumper @_;
}

sub D_QUIET {
    my $opt = ref $_[0] eq 'HASH' ? shift : {};
    # first one white
    $opt->{white} //= 1;

    my $do_encode_utf8 = $opt->{no_utf8} ? 0 : 1;

    $Debug_level > 0 or return;

    my @c = (BB, Y);

    # in case of disable_colors
    my $r = RESET;
    $r //= '';

    my $i = 0;
    my $s;
    $s = $c[0] . '[nothing]' . $r unless @_;
    my $first = 1;

    for (@_) {
        local $_ = $_;
        $_ //= '[undef]';
        if ($_ ne '0') {
            $_ ||= '[empty]';
        }
        utf8::encode($_) if $do_encode_utf8;
        my $c;
        if ($opt->{white} and $first) {
            $c = $r;
            $first = 0;
        }
        else {
            $c = $c[$i++ % 2];
        }

        # if disable_colors was called
        $c //= '';

        $s .= sprintf "%s%s ", $c, $_;
    }
    return "$s" . $r . "\n";
}

sub D_RAW {
    $Debug_level > 0 or return;
    print D_QUIET({no_utf8 => 1}, @_);
}

sub D2_RAW {
    $Debug_level > 1 or return;
    print D_QUIET({no_utf8 => 1}, @_);
}

sub DC {
    D {white=>0}, @_;
}

sub DC_QUIET {
    D_QUIET {white=>1}, @_;
}

sub D {
    $Debug_level > 0 or return;
    #print D_QUIET(@_);
    warn D_QUIET(@_) . "\n";
}

sub D2 {
    $Debug_level > 1 or return;
    warn D_QUIET(@_) . "\n";
}

sub D3 {
    $Debug_level > 2 or return;
    warn D_QUIET(@_) . "\n";
}

sub _color {
    my ($col, @s) = @_;
    if (-t STDOUT or $Force_colors) {
        if (@s) {
            my $s = join '', grep { defined } @s;

            $Disable_colors and return $s;

            if ($s ne '') {
                return color($col) . $s . color('reset');
            }
            else {
                return color($col);
            }
        }
        else {
            $Disable_colors and return;
            return color($col);
        }
    }
    else {
        my $s = join '', grep { defined } @s;
        return $s;
    }
}

sub list ($) { 
    my $s = shift;
    ref $s eq 'ARRAY' or die "need array ref to list()";
    return @$s;
}

sub hash {
    my $s = shift;
    ref $s eq 'HASH' or die "need hash ref to hash()";
    return %$s;
}

sub is_num {
    local $_ = shift // (warn, return);
    / ^ -? \d+ (\.\d+)? $/x and return 1;
}

sub is_int {
    my $n = shift // die;
    is_num($n) or return 0;
    return $n == int($n);
}

sub is_even {
    my $s = shift // die;
    ( is_num $s and $s >= 0 and is_int $s ) or error "Need non-negative int to is_even";
    return $s % 2 ? 0 : 1;
}

sub is_odd {
    my $s = shift // die;
    ( is_num $s and $s >= 0 and is_int $s ) or error "Need non-negative int to is_odd";
    return $s % 2 ? 1 : 0;
}


sub field {
    my ($width, $string, $len) = @_;
    $len //= length $string;
    my $num_spaces = $width - $len;
    if ($num_spaces < 0) {
        warn sprintf "Field length (%s) bigger than desired width (%s)", $len, $width;
        return $string;
    }
    return $string . ' ' x ($width - $len);
}

sub remove_quoted_strings {
    my $s = shift or return '';
    my @s = split //, $s;
    my @new;
    my $in = 0;
    my $qc = '';
    my $prev = '';
    for (@s) {
        if (! $in) {
            if ( $_ eq "'" or $_ eq '"' ) {
                $in = 1;
                $qc = $_;
            }
            else {
                push @new, $_;
            }
        }
        else {
            if ( $qc eq "'" ) {
                if ($_ eq "'" and $prev ne '\\') {
                    $in = 0;
                    $qc = '';
                }
            }
            elsif ( $qc eq '"' ) {
                if ($_ eq '"' and $prev ne '\\') {
                    $in = 0;
                    $qc = '';
                }
            }
            else {
                # ignore
            }
        }
        $prev = $_;
    }
    return join '', @new;
}
    
sub bench_start { 
    _bench(0, @_); 
}
sub bench_end { 
    _bench(1, @_); 
}
sub bench_pr {
    _bench(2, @_); 
}
sub bench_end_pr {
    bench_end(@_);
    bench_pr(@_);
}

sub _bench {
    my ($a, $id) = @_;

    state %start;
    state %total;
    state %idx;

    # start
    if ($a == 0) {
        $start{$id} = time;
        $total{$id} //= 0;
        $idx{$id}++;
    }
    # end
    elsif ($a == 1) {
        $total{$id} += time - $start{$id};
        delete $start{$id};
    }
    # print
    elsif ($a == 2) {
        say '';
        say sprintf 'Bench: (id %s) (counts %d)', BB $id, $idx{$id};
        print ' ', D_QUIET $id, $total{$id} // die "Unknown id ", Y $id;
    }
    else { die }
}

sub nice_bytes ($) {
    # bytes
    my $n = shift;
    if ( $n < 1024 ) {
        return sprintf("%d", $n), 'b';
    }
    elsif ( $n < 1024 ** 2 ) {
        return sprintf("%.1f", $n / 1024), 'K';
    }
    elsif ( $n < 1024 ** 3) {
        return sprintf("%.1f", $n / 1024 ** 2), 'M';
    }
    else {
        return sprintf("%.1f", $n / 1024 ** 3), 'G';
    }
}

sub nice_bytes_join ($) {
    return join '', nice_bytes shift;
}

sub get_file_no {
    my ($fh) = @_;
    $fh or war ("fh is undef"), return;
    my $fn = fileno($fh);
    my $ok = $fn && $fn != -1;
    return $ok ? $fn : undef;
}

sub pad($$) {
    my ($length, $str) = @_;
    my $l = length $str;
    return $l >= $length ? $str :
        $str . ' ' x ($length - $l);
}

# bi-dir-pipe:

#use IPC::Open2;
#my $pid = open2(my $fh_r, my $fh_w, $cmd);
#print $fh_w $q;
#close $fh_w;
#say while <$fh_r>;

sub e8($) {
    my $s = shift;
    utf8::encode $s;
    $s;
}

sub d8($) {
    my $s = shift;
    utf8::decode $s;
    $s;
}

# e.g. while (is_defined my $a = pop @b) { }
# no prototype, or else that won't work.
sub is_defined { defined shift }
sub def { defined shift }

sub rl {
    my ($fh) = @_;
    my $in = <$fh> // return;
    chomp $in;
    $in;
}

sub unshiftr { unshift @{shift @_}, @_ }
sub pushr { push @{shift @_}, @_ }
sub shiftr { shift @{shift @_} }
sub popr { pop @{shift @_} }
sub scalarr { scalar @{shift @_} }
sub keysr { keys %{shift @_} }

sub eachr { 
    my ($r) = @_;
    return ref $r eq 'ARRAY' ? 
        each @$r :
        ref $r eq 'HASH' ?
        each %$r : 
        (warn, undef);
}

# Called as:
# contains $arrayref, $search
sub containsr {
    my ($ary, $search) = @_;
    first { $_ eq $search } @$ary;
}

# Called as:
# contains @array, $search
sub contains (+$) {
    my ($ary, $search) = @_; # $ary is indeed a reference
    return containsr $ary, $search;
}

sub slurp {
    my ($arg, $opt) = @_;
    local $/ = undef;
    if (ref $arg eq 'GLOB') {
        return <$arg>;
    }
    else {
        # caller can set no_die in opt
        my $fh = safeopen $arg, $opt or warn, return;
        return <$fh>;
    }
}

sub slurp8 {
    my ($arg, $opt) = @_;
    $opt ||= {};
    $opt->{utf8} = 1;
    return slurp($arg, $opt);
}

sub slurpn($$) {
    my ($size, $arg) = @_;
    _slurpn($size, $arg, 0);
}
sub slurpn8($$) {
    my ($size, $arg) = @_;
    _slurpn($size, $arg, 1);
}

sub _slurpn {
    my ($size, $arg, $utf8) = @_;
    my $bytes;
    if ($size =~ /\D/) {
        if ($size =~ / ^ (\d+) ([bkmg]) $/ix) {
            my $mult = { b => 1, k => 1e3, m => 1e6, g => 1e9, }->{lc $2};
            $bytes = $1 * $mult;
        }
        else {
            error "Invalid size for slurpn:", BR $size;
        }
    }
    else {
        $bytes = $size;
    }
    if (ref $arg eq 'GLOB') { 
        # Can't get file size -- just read the given amount of bytes.
        my $in;
        sysread $arg, $in, $bytes or war("Couldn't read from fh"),
            return;

        my $is_stdin = do {
            # STDIN could be duped, in which case it gets a new fileno: open my $fh, ">&STDIN"
            # STDIN could be copied, in which case fileno is the same: open my $fh, "<&=STDIN"
            # And File::stat doesn't work with STDIN.
            my $stdin = safeopen "<&=STDIN", {die => 0} or last;
            fileno($arg) == fileno STDIN                ? 1 :
            ((stat $stdin)->ino == (stat $arg)->ino)    ? 1 :
            0;
        };

        war "Filehandle not completely slurped." if not $is_stdin and not eof $arg;

        return $utf8 ? d8 $in : $in;
    }
    else {
        my $file_size = -s $arg;
        defined $file_size or war (sprintf "Can't get size of file %s: %s", R $arg, $!),
            return;
        $file_size <= $bytes or war (sprintf "File too big (%s), not slurping.", $file_size), 
            return;
        return $utf8 ? slurp8 $arg : slurp $arg;
    }
}

sub cat {
    my $file = shift;
    my $fh = safeopen $file, { die => 0 } or warn, return;
    local $/ = undef;
    my $a = <$fh>;
    say $a;
}

sub chompp(_) {
    my ($s) = @_;
    chomp $s;
    $s;
}

sub free_space {
    my ($file) = @_;

    #Filesystem     1K-blocks     Used Available Use% Mounted on
    #/dev/sda7       59616252 59616252         0 100% /stuff

    my ($l, $code, $err) = sysl qq, df "$file" ,,;
    if ($code) { 
        warn join ' ', list $l;
        return -1;
    }
    else {
        my $s = $l->[1] or warn, return;
        my @split = (split /\s+/, $s);
        my $part = $split[0] or warn, return;
        my $space = $split[3];
        defined $space or warn, return;
        return wantarray ? ($space, $part) : $space;
    }
}


1;
