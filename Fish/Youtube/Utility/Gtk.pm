package Fish::Youtube::Utility::Gtk;

use 5.10.0;

BEGIN {
    use Exporter ();
    @ISA = qw/Exporter/;
    @EXPORT_OK = qw/
    /;
    @EXPORT = qw/
        sanitize_pango unsanitize_pango

        sig timeout set_cursor normal_cursor set_cursor_timeout
        get_color
    /;
}

use 5.10.0;

use strict;
use warnings;

use utf8;

use Gtk2;

my %SANITIZE_PANGO = (
    '&' => '&amp;',
);

sub sig {
    my ($w, $sig, $sub) = @_;
    $w->signal_connect($sig, $sub);
}

sub timeout {
    my ($time, $sub) = @_;

    # Timeouts are called outside of the main lock loop and so you need to
    # put enter/leave around them.

    my $new = sub {
        Gtk2::Gdk::Threads->enter;
        # always scalar -- return is 0 or 1
        my $r = $sub->(@_);
        Gtk2::Gdk::Threads->leave;
        $r;
    };
    Glib::Timeout->add($time, $new);
}

sub set_cursor_timeout {
    shift if $_[0] eq __PACKAGE__;
    my ($widget, $curs) = @_;
    timeout(50, sub { 
        return ! set_cursor($widget, $curs) 
    } );
}


sub set_cursor {

    my ($widget, $curs) = @_;
    if (my $w = $widget->window) {
        $w->set_cursor(Gtk2::Gdk::Cursor->new($curs));
        return 1;
    }
    return 0;
}

sub normal_cursor {
    my ($w) = shift;
    set_cursor($w, 'left-ptr');
}

# 0-255
sub get_color {
    shift if $_[0] eq __PACKAGE__;
    my ($r, $g, $b, $a) = @_;
    for ($r, $g, $b, $a) {
        $_ > 255 and die;
        $_ < 0 and die;
        $_ *= 257;
    }
    Gtk2::Gdk::Color->new($r, $g, $b, $a);
}

# ref
sub sanitize_pango {
    my $r = shift;
    while (my ($k, $v) = each %SANITIZE_PANGO) {
        $$r =~ s/\Q$k\E/$v/g;
    }
}

sub unsanitize_pango {
    my $r = shift;
    while (my ($k, $v) = each %SANITIZE_PANGO) {
        $$r =~ s/\Q$v\E/$k/g;
    }
}


1;

