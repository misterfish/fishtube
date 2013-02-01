package Fish::Youtube::Utility;

use 5.10.0;

BEGIN {
    use Exporter ();
    @ISA = qw/Exporter/;
    @EXPORT_OK = qw/
        mywait round 
        get_date get_date_2 
        sayf RESETR
        bench_start bench_end bench_end_pr bench_pr
        remove_quoted_strings
    /;
    @EXPORT = qw/
        $CROSS $CHECK
        sys sys_chomp sys_ok sysl safeopen sys_return_code datadump
        strip strip_ptr 
        yes_no disable_colors
        list hash pad
        disable_colors
        R G B BR BB CY Y RESET
        D d D2 D3 D_QUIET D_RAW DC DC_QUIET
        randint is_int field is_num
        nice_bytes nice_bytes_join o
        unshift_r shift_r pop_r push_r
    /;
}

use 5.10.0;

use strict;
use warnings;

use utf8;

use Term::ANSIColor;
use Carp 'confess';
use Data::Dumper;

use constant _CLASS_GENERATE => 1;

# make simple singleton classes for keeping global space neat and also gives
# us -> accessors
use if _CLASS_GENERATE, 'Class::Generate' => 'class';

# for bench
use Time::HiRes 'time';

our $VERBOSE = 0;

our $LOG_LEVEL = 1;
our $Disable_colors = 0;

our $CHECK = '✔';
our $CROSS = '✘';

sub D;
sub D2;
sub D3;
sub D_QUIET;

sub error;

# ; means optional.

sub R (;$)          { return -t STDOUT ? _color('red', @_) : ($_[0] // '') }
sub BR (;$)         { return -t STDOUT ? _color('bright_red', @_) : ($_[0]
        // '') }
sub G (;$)          { return -t STDOUT ? _color('green', @_) : ($_[0] // '') }
sub B (;$)          { return -t STDOUT ? _color('blue', @_) : ($_[0] // '') }
sub BB (;$)         { return -t STDOUT ? _color('bright_blue', @_) : ($_[0]
    // '')}
sub CY (;$)         { return -t STDOUT ? _color('cyan', @_) : ($_[0] // '') }
sub Y (;$)          { return -t STDOUT ? _color('yellow', @_) : ($_[0] //
        '') }
sub RESET           { return -t STDOUT ? _color('reset') : '' }

sub disable_colors { 
    $Disable_colors = 1;
}

sub sys_chomp {
    my ($ret, $code) = sys(@_);
    chomp $ret;
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
    
    my $wants_list;
    my $kill_err;

    my $opt;

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
    $verbose //= $VERBOSE;

    $wants_list = $opt->{list} // 0;
    $kill_err = $opt->{killerr} // 0;

    my @out;
    my $out;
    my $ret;

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
        say "Executing:\n$command" if $verbose;
        if ($wants_list) {
            @out = map { chomp; $_} `$command`;
        } else {
            $out = `$command`;
        }
        $ret = $?;
    }
    my $err = $!;
    if ($ret && $die) {
        my $out_to_print = $out || join "\n", @out;
        $err ||= "(no err string)";
        $out and $err .= " (output: $out)";
        confess $err;
    }

    # perl thing
    $ret >>= 8 if defined $ret;

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
    return ! sys_return_code(@_);
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



sub round {
    my $s = shift;
    my ($s_int, $s_frac) = ( int ($s), $s - int ($s) );
    if ($s_frac >= .5) {
        return $s_int + 1;
    } else {
        return $s_int;
    }
}

sub safeopen {
    (scalar @_ < 3) || error("safeopen() called incorrectly");

    my $file = shift or error "Need file for safeopen()";

    my $die;
    my $is_dir;

    my $arg2 = shift;

    my $utf8;
    if (ref $arg2 eq 'HASH') {
        # require an arg to open dirs, to avoid mistakes.
        $die = $arg2->{die};
        $is_dir = $arg2->{dir};
        $utf8 = $arg2->{utf8} || $arg2->{UTF8} || $arg2->{'utf-8'} || $arg2->{'UTF-8'};
    }
    # old form
    else {
        $die = $arg2;
    }

    $die //= 1;

    if ( -d $file ) {
        if (! $is_dir) {
            warn "Deprecated -- need opt 'dir => 1' to use safeopen with a dir.";
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
        return $fh;
    } else {
        $die and error "Couldn't open filehandle to", R $file, "for", Y $op, "--", R $!;
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

sub error {
    my @s = @_;
    die join ' ', @s, "\n";
}

sub find_cdrecord {
    my $DEV_SEARCH = 'FREECOM';
    local $\ = "\n";
    if ( `whoami` ne "root\n" ) {
        print STDERR "find_cdrecord: " . "Must be run as root";
        return '';
    }

    my $cmd = 'cdrecord -scanbus';
    $_ = `$cmd`;
    if ($?) {
        print STDERR "find_cdrecord: " . "Couldn't do: $cmd; $!";
        return '';
    }

    my $DEV = (/(\d,\d,\d).+?$DEV_SEARCH/)[0];
    if ( ! $DEV ) {
        print STDERR "find_cdrecord: " . "Couldn't find device. Searched for $DEV_SEARCH. Output of $cmd: $_";
        return '';
    }

    return $DEV;
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
    my $infinite = $opt->{infinite} // 1;
    my $print = "(y/n) ";
    local $\ = undef;
    while (1) {
        printf "$print";
        my $in = <STDIN>;
# weird case.        
#defined $in or return 0;
        chomp $in;
        if ($in =~ /^\s*y\s*$/i) {
            return 1;
        }
        elsif ($in =~ /^\s*n\s*$/i) {
            #exit 1;
            return 0;
        }
        # not y or n
        elsif ( ! $infinite) {
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

    $LOG_LEVEL > 0 or return;

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
    $LOG_LEVEL > 0 or return;
    print D_QUIET({no_utf8 => 1}, @_);
}

sub DC {
    D {white=>0}, @_;
}

sub DC_QUIET {
    D_QUIET {white=>1}, @_;
}

sub D {
    $LOG_LEVEL > 0 or return;
    print D_QUIET(@_);
}

sub D2 {
    $LOG_LEVEL > 1 or return;
    say D_QUIET(@_);
}

sub D3 {
    $LOG_LEVEL > 2 or return;
    say D_QUIET(@_);
}

sub _color {
    my ($col, @s) = @_;
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
    local $_ = shift // die;
    / ^ -? \d+ (\.\d+)? $/x and return 1;
}

sub is_int {
    my $n = shift // die;
    is_num($n) or return 0;
    return $n == int($n);
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
    if ( $n < 2 ** 10 ) {
        return sprintf("%d", $n), 'b';
    }
    elsif ( $n < 2 ** 20 ) {
        return sprintf("%.1f", $n / 2 ** 10), 'K';
    }
    elsif ( $n < 2 ** 30) {
        return sprintf("%.1f", $n / 2 ** 20), 'M';
    }
    else {
        return sprintf("%.1f", $n / 2 ** 30), 'G';
    }
}

sub nice_bytes_join ($) {
    return join '', nice_bytes shift;
}

sub pad($$) {
    my ($length, $str) = @_;
    my $l = length $str;
    return $l >= $length ? $str :
        $str . ' ' x ($length - $l);
}

# generate anonymous object with -> accessors.

# e.g.:
# $obj = o( a=>1, b=>undef, %hash=>{}, hash_ref=>{}, @ary=>[], ary_ref=>[],
# '+-idx' => -1)

sub o {
    die "generate is disabled" unless _CLASS_GENERATE;
    state $idx = 0;
    my %stuff = @_;
    my $class_name = 'anon' . ++$idx;
    my (@class_def, @init);
    while (my ($k, $v) = each %stuff) {
        my $sigil;
        my $add_counter_methods;
        if ($k =~ /^ ( % | @ | \+- ) (.+) /x) {
            if ($1 eq '+-') {
                $sigil = '$';
                $add_counter_methods = 1;
                $k = $2;
            }
            else {
                $sigil = $1;
                $k = $2;
            }
        }
        else {
            $sigil = '$';
        }
        push @class_def, $k, $sigil;
        push @init, $k,  $v;

        # if var name is e.g. +-idx, this adds magic methods ->idx_inc and
        # ->idx_dec.
        if ($add_counter_methods) {
            # e.g. push @class_def, '&idx_inc' => q{ $idx++ }
            # man Class::Generate
            push @class_def, "&${k}_inc", qq{ \$$k++ };
            push @class_def, "&${k}_dec", qq{ \$$k-- };
        }

    }

    # class anon1 => [ x => '$', y => '%', ... ];
    #class $class_name => [ @class_def ];
    class $class_name => { @class_def };

    my $obj = $class_name->new(@init);

    return $obj;
}

sub unshift_r { unshift @{shift @_}, @_ };
sub push_r { push @{shift @_}, @_ };
sub shift_r { shift @{shift @_} };
sub pop_r { pop @{shift @_} };

1;
