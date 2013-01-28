package Fish::Youtube::Gtk;

# needs refactor -- too much crap in this module

use 5.10.0;

use strict;
use warnings;

use threads;
use threads::shared;

use Gtk2 qw/ -init -threads-init /;
use Gtk2::SimpleList;

use Gtk2::Pango;

die "Glib::Object thread safety failed" unless Glib::Object->set_threadsafe (1);

use Fish::Youtube::Utility;
use Fish::Youtube::Download;

my $D = 'Fish::Youtube::Download';

use Time::HiRes 'sleep';

use File::stat;
use File::Basename;

use Math::Trig ':pi';

#%

# make up a unique id
use constant STATUS_OD => 100;

use File::Slurp;

sub timeout;

sub err;
sub error;
sub war;
sub mess;
sub max;

my $pane_pos;

my $inited;

my $im;

my $tree_data_magic;

my $Script_dir = dirname $0;
my $IMAGES_DIR = $Script_dir . '/../images';

-d $IMAGES_DIR or error "Images dir", Y $IMAGES_DIR, "doesn't exist.";
-r $IMAGES_DIR or error "Images dir", Y $IMAGES_DIR, "not readable";

my %IMG = (
    add                 => 'add-12.png',
    cancel              => 'cancel-20.png',
    cancel_hover        => 'cancel-20-hover.png',
);

my %Img;
for (qw/ add cancel cancel_hover /) {
    my $i = "$IMAGES_DIR/$IMG{$_}";
    -r $i or error "Image", Y $i, "doesn't exist or not readable.";
    $Img{$_} = $i;
}

my $Height = 300;
# calculated
my $Width;

my $WID_PERC = .75;

my $WP = 100;
my $HP = 100;

my $RIGHT_SPACING_H_1 = 10;
my $RIGHT_SPACING_H_2 = 10;
my $RIGHT_PADDING_TOP = 20;

# start watching when this perc downloaded.
my $AUTO_WATCH_PERC = 10;

my $RIGHT_SPACING_V = 15;

my $Scrollarea_height = $RIGHT_PADDING_TOP;

# separation proportion
my $PROP = .5;

my $w;
my $list;
my $hp;

my $output_dir;

my $layout;
#my $wait_box;
my $STATUS_PROP = .7;
my $status_bar;
my $status_bar_dir;

use Fish::Youtube::Anarchy;

# left pane
my @movie_data;

# mid => text
my %is_waiting;

my %download_buf;

my $pixmap_base;

# right
my $labels_box;

my $last_mid = -1;
my $last_idx = -1;

my @movies_buf;

my $gc;

# mid => [
# 0 cur_size
# 1 '/'
# ]
my %size_label;

my %info_box;
my %cancel_images;

#^

my %auto_launched;

my $OUTPUT_DIR_TXT = "Output dir:";

my $last_mid_in_statusbar;
my $INFO_X = $WP + $RIGHT_SPACING_H_1 + $RIGHT_SPACING_H_2;

my %download_successful;

#my %wait_l;

my $white = get_color(255,255,255,255);
my $black = get_color(0,0,0,255);

sub init {

    Gtk2::Gdk::Threads->enter;

    my ($class, $od, $opt) = @_;
    $opt //= {};

    my $od_ask;
    if ($od) {
        set_output_dir($od);
    }
    else {
        $od_ask = 1;
    }

    # hash of name => dir
    my $profile_ask = $opt->{profile_ask};

    $w = Gtk2::Window->new('toplevel');

    my $scr = $w->get_screen;
    my $wid = $scr->get_width;
    if (! $wid) {
        warn "couldn't get screen width";
        $Width = 800;
    }
    else {
        $Width = $wid * $WID_PERC;
    }

    $w->set_default_size($Width, $Height);
    $w->modify_bg('normal', $white);

    $w->signal_connect('configure_event', \&configure_main );
    $w->signal_connect('destroy', sub { $w->destroy; exit 0 } );

    my $l = Gtk2::VBox->new;
    
    my $l_buttons = Gtk2::HBox->new;

    my $lw = Gtk2::ScrolledWindow->new;

    $l->pack_start($l_buttons, 0, 0, 10);

    my $lwf = Gtk2::Frame->new;
    $lwf->add($lw);
    $l->add($lwf);

    #my $button_add = Gtk2::Button->new_from_stock('gtk-add');
    my $button_add = Gtk2::EventBox->new;
    $button_add->add(Gtk2::Image->new_from_file($Img{add}));
    $button_add->signal_connect('button-press-event', sub {
        my $response = inject_movie();
    });
    $button_add->modify_bg('normal', $white);

    set_cursor_timeout($button_add, 'hand2');

    $l_buttons->pack_start($button_add, 0, 0, 10);

    $lw->set_policy('never', 'automatic');

    # is a TreeView
    $list = Gtk2::SimpleList->new ( 
        ''    => 'text',
    );

    $list->set_headers_visible(0);

    $lw->add($list);
    $lw->show_all;

    # tree_data_magic is tied
    $tree_data_magic = $list->{data};

    $list->signal_connect (row_activated => sub { row_activated(@_) });

    $hp = Gtk2::HPaned->new;

    set_pane_position($Width);

    my $outer_box = Gtk2::VBox->new;

    $status_bar = Gtk2::Statusbar->new;
    #$status_bar_dir = Gtk2::Statusbar->new;
    $status_bar_dir = Gtk2::Label->new;

    # want to flush label right but doesn't work
    my $status_bar_dir_box = Gtk2::EventBox->new;
    $status_bar_dir_box->modify_bg('normal', $white);
    my $status_bar_dir_box_al = Gtk2::Alignment->new(1, 0, 0, 0);
    $status_bar_dir_box_al->add($status_bar_dir_box);
    $status_bar_dir_box->add($status_bar_dir);
    set_cursor_timeout($status_bar_dir_box, 'hand2');

    $status_bar_dir_box->signal_connect('button-press-event', sub {
        do_output_dir_dialog();
    });

    $status_bar_dir->modify_bg('normal', $black);

    # expand, fill, padding
    # fill has no effect if expand is 0.
    $outer_box->pack_start($hp, 1, 1, 0);

    # row, col, homog
    my $status_table = Gtk2::Table->new(1, 2, 0);
    # leftmost col, rightmost col, uppermost row, lower row, optx, opty, padx, pay
    my $oo = [qw/ expand shrink fill /];
    my $ooo = 'shrink';
    $status_table->attach($status_bar, 0, 1, 0, 1, $oo, $oo, 10, 10);
    $status_table->attach($status_bar_dir_box_al, 1, 2, 0, 1, $ooo, $ooo, 10, 10);

    $status_bar->set_size_request($Width * .7, -1);
    $status_bar_dir->set_size_request($Width * .3, -1);

    set_label($status_bar_dir, "$OUTPUT_DIR_TXT", { size => 'small', color
=> 'red'});

    $_->set_has_resize_grip(0) for $status_bar;
    #$status_box->pack_start($status_bar, 1, 1, 10);
    #$status_box->pack_end($status_bar_dir, 1, 1, 10);

    $outer_box->pack_end($status_table, 0, 0, 10);

    $w->add($outer_box);

    my $r;

    $r = Gtk2::ScrolledWindow->new;
    $r->set_policy('never', 'automatic');

    $hp->child2_shrink(1);

    $hp->pack1($l, 0, 1);

    $layout = Gtk2::Layout->new;
    $layout->signal_connect('expose_event', \&expose_drawable );
    $layout->modify_bg('normal', $white);

    $r->add($layout);

    $hp->pack2($r, 0, 1);

    $w->show_all;

    $w->set_app_paintable(1);

    # why ever set to 0?
    #$w->set_double_buffered(0);

    # pane moved
    $hp->get_child1->signal_connect('size_allocate', sub { 
        $pane_pos = $hp->get_position;
        $w->queue_draw;
    });

    timeout(50, sub {

            if ($D->is_anything_drawing) {
                #Gtk2::Gdk::Threads->enter;
                # And all children.
                $w->queue_draw;
                #Gtk2::Gdk::Threads->leave;
            }
        1;
    });

    timeout(1000, sub { 
        update_movie_tree() ;
    });


#my $SIMULATE = 0;
#my $sim_idx = 0;
#$SIMULATE and timeout(1000, sub {
#    ++$last_mid;
#    my $mid = $last_mid;
#    $prog{$mid} = 0;
#    my $size = int rand 1e6;
#    add_download($mid, 'blah', $size, '/tmp/t.flv');
#
#    my $this_mid = $mid;
#
#    # 100 times
#    timeout(100, sub {
#        $prog{$this_mid} += $size / 100;
#        $prog{$this_mid} >= $size and D2 'done' and return 0;
#        return 1;
#    });
#    return ++$sim_idx == 10 ? 0 : 1;
#});

    my @init_chain;

    if ($profile_ask) {
        push @init_chain, sub {
            my $pd = profile_dialog($profile_ask);
            main::set_profile_dir($pd);
        };
    }

#    if ($od_ask) {
#        push @init_chain, \&do_output_dir_dialog;
#    }

    push @init_chain, sub { $inited = 1 };

    my $chain = sub {

        #Gtk2::Gdk::Threads->enter;

        $_->() for @init_chain;

        #Gtk2::Gdk::Threads->leave;
        0;
    };
    timeout 100, $chain;

    timeout 100, \&poll_downloads;

    # make Y, R, etc. no-ops
    disable_colors();

    # internally releases lock on each iter.
    Gtk2->main;
    Gtk2::Gdk::Threads->leave;
}

sub inited {
    return $inited;
}

sub set_buf {
    my ($class, $_movies_buf) = @_;
    #@movies_buf: latest in front
    unshift @movies_buf, $_ for reverse @$_movies_buf;
}

sub update_movie_tree {

    state $last;
    state $first = 1;

    my $i = 0;

    @movies_buf or return 1;

    # single value of {} means History returned exactly 0 entries
    {
        my $m = shift @movies_buf;
        if (! %$m) {
            @$tree_data_magic = "No movies -- first browse somewhere in Firefox.";
            return 1;
        }
        else {
            unshift @movies_buf, $m;
        }
    }

    if ($first) {
        @$tree_data_magic = ();
        $first = 0;
    }

    #@movies_buf: latest in front

    my @m = @movies_buf;
    @movies_buf = ();

    my @n;

    if ($last) {
        for (@m) {
            my ($u, $t) = ($_->{url}, $_->{title});
            $u eq $last and last;
            push @n, $_;
        }
    }
    else {
        @n = @m;
    }

    # tree data magic ... enter/exit necessary?

    for (reverse @n) {
        my ($u, $t) = ($_->{url}, $_->{title});

        $t =~ s/ \s* - \s* youtube \s* $//xi;

        $last_mid++;
        unshift @$tree_data_magic, $t;
        unshift @movie_data, { mid => $last_mid, url => $u, title => $t};

        # first in buffer is last
        $last = $u if ++$i == @n;
    }
    # keep going
    1;
}


sub timeout {
    my ($time, $sub) = @_;
    my $new = sub {
        Gtk2::Gdk::Threads->enter;
        my $r = $sub->(@_);
        Gtk2::Gdk::Threads->leave;
        $r;
    };
    Glib::Timeout->add($time, $new);
}

# 0-255
sub get_color {
    my ($r, $g, $b, $a) = @_;
    for ($r, $g, $b, $a) {
        $_ > 255 and die;
        $_ < 0 and die;
        $_ *= 257;
    }
    Gtk2::Gdk::Color->new($r, $g, $b, $a);
}

sub row_activated {
    my ($obj, $path, $column) = @_;

    if (! $output_dir) {
        # remove_all doesn't seem to work.
        $status_bar->pop(STATUS_OD);
        $status_bar->push(STATUS_OD, 'Choose output dir first.');
        return;
    }


    my $row_idx = $path->get_indices;
    my $d = $movie_data[$row_idx] or die;
    my ($u, $t, $mid) = ($d->{url}, $d->{title}, $d->{mid});

    start_download($u, $t, $mid);
}

sub start_download {
    my ($u, $t, $mid) = @_;

    # already downloaded
    return if $D->exists($mid);
    
    $download_successful{$mid} = 0;
    $auto_launched{$mid} = 0;

    my $box;

    my $tmp = main::get_tmp_dir();

    my $wait_s = "Trying to get '";
    $wait_s .= $t ? $t : 'manual download';
    $wait_s .= "' ";
    $is_waiting{$mid} = $wait_s;

    $last_mid_in_statusbar = $mid;
    $status_bar->push($mid, $wait_s);

    state $first = 1;

    my $manual;
    my $of;

    # manual download -- get name from youtube-get
    if (! $t) {
        $manual = 1;
    } 
    
    else {
        $t =~ s/^\s+//;
        $t =~ s/\s+$//;

        $t =~ s/[\n:!\*<>\`\$]//g;

        $t =~ s|/|-|g;
        $t =~ s|\\|-|g;
        $t =~ s/"/'/g;

        $of = "$output_dir/$t.flv";

        if (-r $of) {
            my $dialog = Gtk2::MessageDialog->new ($w,
                'modal',
                'question', # message type
                'yes-no', # which set of buttons?
                "File '%s' exists; overwrite?", $of);

            my $response;

            $dialog->signal_connect('response', sub {
                my ($self, $res) = @_;
                $response = $res;
                $dialog->destroy;
            });

            $dialog->run;

            if ($response ne 'yes') {
                return;
            }

            if (! sys_ok qq, rm -f "$of", ) {
                mess "Couldn't remove file", Y $of;
                return;
            }
        }
    }

    # add puntjes to waiting msg
    timeout(300, sub {
        my $text;
        return 0 unless $last_mid_in_statusbar == $mid;
        return 0 unless $text = $is_waiting{$mid};

        $text .= '.';
        $status_bar->pop($mid);
        $status_bar->push($mid, $text);
        $is_waiting{$mid} = $text;
        1;
    });

    $layout->show_all;

    if ($first) {
        set_pane_position($Width / 2);
        $first = 0;
    }

    # make some of these vars internal to main todo
    my ($pid, $err_file) = main::start_download($mid, $u, ($manual ? undef : $of), $tmp, $output_dir);

    if (!$pid) {
        # subproc failed.
        movie_panic_while_waiting($err_file, $mid);
        return;
    }

    my $i = 0;

    # wait for forked proc to tell us something.
    timeout(2000, sub {
        my $size;

        $i++ > 20 and error "youtube-get behaving strange.";

        my ($s, $code) = sys qq, cat 2>/dev/null "$tmp/.yt-file",, 0;
        
        if ($s =~ /(.+)\n(\d+)/) {

            # got name and size from forked proc. officially start download.
           
            my $name;
            ($name, $size) = ($1, $2);

            # name and of are in principle the same. name comes from the
            # parsed html of the fetched page, of comes from the browser
            # cache.
            my $o;
            if ($manual) {
                $o = $name;
                $t = basename $name;
                $t =~ s/\.\w+$//;
            }
            else {
                $o = $of;
            }

            add_download($mid, $t, $size, $o, $pid);

            timeout( 200, sub { 
                return file_progress($mid, $o, $size, $err_file, $pid);
            });

            # ok, stop waiting.
            return 0;
        }

        if (! main::process_running($pid)) {
            # child proc died before we could get the metadata.
            war "Child died", Y $pid;

            movie_panic_while_waiting($err_file, $mid);

            return 0;
        }

        # keep waiting
        return 1;
    });
    # / fork wait


}

sub file_progress {
    my ($mid, $file, $size, $err_file, $pid) = @_;
    my $s = stat $file or warn(), return 1;

    my $d = $D->get($mid);

    # download object destroyed for some reason
    if (! $d) {
        movie_panic($err_file, $mid);
        return 0;
    }

    my $cur_size = $s->size;
    $d->prog($cur_size);

    if (!$auto_launched{$mid}) {
        if ($cur_size / $size * 100 > $AUTO_WATCH_PERC) {
            $auto_launched{$mid} = 1;
            main::watch_movie($file);
        }
    }

    D2 'cur_size', $cur_size;

    if ($cur_size == $size) {
        download_finished($mid);
        return 0;
    }
    else {
        # killed
        # ps, heavy?
        if ( ! sys_ok "ps $pid") {
            movie_panic($err_file, $mid);
            return 0;
        }
    }
    return 1;
}

sub add_download {

    my ($mid, $title, $size, $of, $pid) = @_;

    # downloads added faster than poll_downloads can grab them (shouldn't
    # happen)
    warn "download buf not empty" if %download_buf;

    %download_buf = (
        idx => ++$last_idx,
        mid => $mid,
        size => $size,
        title => $title,
        of => $of,
        pid => $pid,
    );
}

sub poll_downloads {

    %download_buf or return 1;

    # start new download

    my $size = $download_buf{size};
    my $title = $download_buf{title};
    my $idx = $download_buf{idx};
    my $of = $download_buf{of};
    my $pid = $download_buf{pid};

    my $pixmap = make_pixmap();

    my $mid = $download_buf{mid};

    my $d = $D->new(
        # main id = mid
        id      => $mid,
        # for drawing pixmaps
        idx     => $idx,
        size    => $size,
        title   => $title,
        of      => $of,
        pid     => $pid,
        pixmap  => $pixmap,
    );

    %download_buf = ();

    my $anarchy = Fish::Youtube::Anarchy->new(
        width => $WP,
        height => $HP,
    );

    my $hb = Gtk2::HBox->new;
    my $vb = Gtk2::VBox->new;
    my $eb = Gtk2::EventBox->new;

    my $c1 = $black;
    my $c2 = get_color(100,100,33,255);
    my $c3 = $c2;
    my $c4 = $c1;

    my $l1 = Gtk2::Label->new;
    set_label($l1, $title, { size => 'small' });
    $l1->modify_fg('normal', $c1);

    my $l2 = Gtk2::Label->new;
    $l2->modify_fg('normal', $c2);
    $size_label{$mid}[0] = $l2;

    my $l3 = Gtk2::Label->new;
    $l3->modify_fg('normal', $c3);
    set_label($l3, '/', { size => 'small' });
    $size_label{$mid}[1] = $l3;

    my $l4 = Gtk2::Label->new;
    set_label($l4, nice_bytes_join $size, { size => 'small' });
    $l4->modify_fg('normal', $c4);

    my $im = Gtk2::Image->new;

    my $pix_normal = Gtk2::Gdk::Pixbuf->new_from_file($Img{cancel});
    my $pix_hover = Gtk2::Gdk::Pixbuf->new_from_file($Img{cancel_hover});
    $im->set_from_pixbuf($pix_normal);

    my $eb_im = Gtk2::EventBox->new;
    $eb_im->add($im);
    $eb_im->modify_bg('normal', $black);
    $im->modify_bg('normal', $black);

    $eb_im->signal_connect('enter-notify-event', sub {
        $im->set_from_pixbuf($pix_hover);
    });

    $eb_im->signal_connect('leave-notify-event', sub {
        $im->set_from_pixbuf($pix_normal);
    });

    $vb->add($l1);
    $hb->add($l2);
    $hb->add($l3);
    $hb->add($l4);

    my $hb_al = Gtk2::Alignment->new(0,0,0,0);
    $hb_al->add($hb);
    $vb->add($hb_al);
    $hb->pack_start($eb_im, 0, 0, 20);

    $_->modify_bg('normal', $white) for $l1, $l2, $l3, $l4, $vb, $eb, $hb, $eb_im;

    $info_box{$mid} = $eb;

    $eb->add($vb);

    remove_wait_label($mid);

    $layout->put($eb, $INFO_X, $RIGHT_PADDING_TOP + $idx * ($HP + $RIGHT_SPACING_V));

    $eb->signal_connect('button-press-event', sub {
        main::watch_movie($of);
    });

    update_scroll_area(+1);
    $layout->show_all;

    set_cursor_timeout($info_box{$mid}, 'hand2');

    $cancel_images{$mid} = $im;

    $eb_im->signal_connect('button-press-event', sub {
        cancel_download($mid);
        # 1 means don't propagate (we are inside $eb)
        return 1;
    });

    # check size, update download status, update pixmap
    timeout(50, sub {

        my $d = $D->get($mid) or return 0;
        #$d->is_downloading or return 0;
        $d->is_drawing or return 0;

        state $last = -1;
        $size // return 1;

        #Gtk2::Gdk::Threads->enter;

        my $err;

        # get every time.
        my $pixmap = $d->pixmap;

        my $p = $d->prog;
        if (not defined $p) {
            D2 "p not defined (yet)";
            # try again
            Gtk2::Gdk::Threads->leave;
            return 1;
        }

        # shouldn't happen
        if (not $pixmap) {
            warn "pixmap not defined";
            # don't try again
            Gtk2::Gdk::Threads->leave;
            return 0;
        }

        my $l = $size_label{$mid}[0];
        $l and set_label($l, nice_bytes_join $p, { size => 'small' });

        my $perc = $p / $size * 100;
        if ($last != $p) {
            my $s = sprintf "%d / %d (%d%%)", $p, $size, $perc;

            # animate here
            my $surface = $anarchy->draw($perc / 100);

            draw_surface_on_pixmap($pixmap, $surface);
        }
        $last = $p;

        #Gtk2::Gdk::Threads->leave;

        if ($perc >= 100) {
            my $surface = $anarchy->draw(1, { last => 1});

            draw_surface_on_pixmap($pixmap, $surface);
            $d->stopped_drawing;
            return 0;
        }
        return 1;
    });

    1;
}

# main window
sub configure_main {
    my ($window, $event) = @_;
    state $x = -1;
    state $y = -1;

    state $first = 1;

    my $ew = $event->width;
    my $eh = $event->height;

    if ($first) {
        $first = 0;
    }
    else {
        return if $ew == $Width and $eh == $Height;
        #D 'configuring', 'width', $ew, 'height', $eh;
    }

    $Width = $ew;
    $Height = $eh;

    # make new pixmaps for all current downloads
    $D->make_pixmaps;

}

sub make_pixmap {
    my ($pw, $ph) = ($WP, $HP);
    my $pixmap = Gtk2::Gdk::Pixmap->new($w->window, $pw, $ph, 24);
    return $pixmap;
}

sub expose_drawable {

    state $i = 0;

    my ($widget, $event, $user_data) = @_;

    my $rect = $event->area;

    $widget or return 1;

    my $print = not $i++ % 20;

    my $x = 10;

    my $gc = $widget->style->fg_gc($widget->state);
    war('no gc'), return unless $gc and ref ($gc) =~ /GC/;

    # Since it's a layout, gotta use bin_window instead of window.
    my $window = $widget->bin_window;

    # check cur
    for my $d ($D->all) {
        my $pixmap = $d->pixmap or warn, next;
        my $idx = $d->idx;

        $window->draw_drawable(
            $gc,
            $pixmap,
            # src
            0, 0,
            # dest
            $x, $RIGHT_PADDING_TOP + $idx * ($HP + $RIGHT_SPACING_V),
            # width, height (-1 for all)
            -1, -1,
        );
    }
}

sub clear_pixmap {
    my $pixmap = shift;
    my ($w, $h) = $pixmap->get_size;
    my $surface = Cairo::ImageSurface->create('argb32', $w, $h);

    my $cr = Cairo::Context->create($surface);

    $cr->set_source_rgba (1, 1, 1, 1);
    # fills the whole thing.
    $cr->paint;

    my $cairo_pixmap = Gtk2::Gdk::Cairo::Context->create($pixmap);
    $cairo_pixmap->set_source_surface($surface, 0,0);
    $cairo_pixmap->paint;
}

sub draw_surface_on_pixmap {
    my ($pixmap, $surface) = @_;
    my $cairo_pixmap = Gtk2::Gdk::Cairo::Context->create($pixmap);
    $cairo_pixmap->set_source_surface($surface, 0,0);
    $cairo_pixmap->paint;
}

sub error {
    my @s = @_;
    die join ' ', @s, "\n";
}

sub war {
    my @s = @_;
    warn join ' ', @s, "\n";
}

sub max {
    my ($a, $b) = @_;
    return $a > $b ? $a : $b;
}

sub download_stopped {
    my ($mid, $nowarn) = @_;
    $nowarn //= 0;
    $D->c_stopped_downloading($mid, $nowarn);
}

sub download_finished {
    my ($mid) = @_;
    download_stopped($mid);
    $_->destroy, undef $_ for $cancel_images{$mid}, list $size_label{$mid};
    $download_successful{$mid} = 1;
}

sub cancel_download {
    my ($mid) = @_;
    my $d = $D->get($mid) or warn, return;
    my $pid = $d->pid or warn, return;
    my $idx = $d->idx;

    if ( ! sys_ok qq, kill $pid , ) {
        err("Couldn't kill process $pid");
        return;
    }

    # will cancel timeouts
    $d->delete;

    $last_idx--;
    # decrease idx of later dls by 1
    for my $d ($D->all) {
        my $j = $d->idx;
        if ($j > $idx) {
            $d->idx_dec;
            my $box = $info_box{$d->id};
            # shift up
            $layout->move($box, $INFO_X, $RIGHT_PADDING_TOP + $d->idx * ($HP + $RIGHT_SPACING_V));
        }
    }
    my $info_box = delete $info_box{$mid};
    $info_box->destroy;

    update_scroll_area(-1);
}

sub set_label {
    my ($label, $text, $opt) = @_;
    my $size = $opt->{size} // '';
    my $color = $opt->{color} // '';

    my $s1 = '';
    my $s2 = '';

    my $ss = $size ? qq|size="$size"|  : '';
    my $sc = $color ? qq|color="$color"| : '';
    my @s = ($ss, $sc);

    $s1 = "<span " . join ' ', @s if @s;
    $s1 .= ">" if $s1;

    $s2 = '</span>' if $s1;

    my $markup = $s1 . $text . $s2;

#D 'markup', $markup;

    my ($al, $txt, $accel_char) = Pango->parse_markup($markup);
    $label->set_attributes($al);
    $label->set_label($text);
}

sub err {
    my ($a, $b) = @_;

    Gtk2::Gdk::Threads->enter;

    # class method or not
    my $s = $b // $a;

    my $dialog = Gtk2::MessageDialog->new ($w,
        'modal',
        'error',
        'close',
    $s);

    $dialog->signal_connect('response', sub { shift->destroy });
    
    $dialog->run;

    Gtk2::Gdk::Threads->leave;
}

sub mess {
    my ($a, $b) = @_;

    # class method or not
    my $s = $b // $a;

    my $d = Gtk2::MessageDialog->new($w,
        'modal',
        'info',
        'ok',
        $s,
    );
    
    $d->run;
    $d->destroy;
}

# +1 when dl is added, -1 when removed
sub update_scroll_area {
    my $i = shift;
    $Scrollarea_height += ($HP + $RIGHT_SPACING_V) * $i;
    # first num just needs to be big
    $layout->set_size(2000, $Scrollarea_height);
}

sub set_pane_position {
    my ($p) = @_;
    $hp->set_position($pane_pos = $p);
}

sub inject_movie {
    my $url = inject_movie_dialog() or return;
    state $i = 0;
    # check url?
    $last_mid++;
    #start_download($url, 'manual ' . ++$i, $last_mid);
    start_download($url, undef, $last_mid);
}

sub make_dialog {
    my $win = shift;

    my $wi = $win // $w;

    my $dialog = Gtk2::Dialog->new;

    $dialog->set_transient_for($wi);
    $dialog->set_position('center-on-parent');
    return $dialog;
}

sub inject_movie_dialog {
    my $dialog = make_dialog();
    my $c = $dialog->get_content_area;
    my $a = $dialog->get_action_area;

    my $l = Gtk2::Label->new;
    set_label($l, 'Manually add URL');
    $c->add($l);

    my $i = Gtk2::Entry->new;
    #$i->set_max_length(80);
    $i->set_size_request(int $Width / 2,-1);


    $dialog->add_action_widget($i, 'apply');

    my $response;
    my $quit;

    $dialog->signal_connect('response', sub {
         my ($self, $str, $data) = @_;
         # enter
         if ($str eq 'apply') {
             my $t = $i->get_text or return;
             $response = $t;
             $dialog->destroy;
             
         }
         elsif ($str eq 'delete-event') {
             $quit = 1;
             $dialog->destroy;
         }
         else {
             war 'unknown response', Y $str;
         }
         D2 'got response', 'str', $str, 'data', $data;
    });

    $dialog->show_all;

    # enter pressed without text.
    # esc sets $quit
    while (! $response and ! $quit) {
        $dialog->run;
    }

    return $response;
}

sub remove_wait_label {
    my ($mid) = @_;
    # my $wait_l = delete $wait_l{$mid} or warn;
    #$wait_l->{l}->destroy;
    $is_waiting{$mid} = 0;
    $status_bar->pop($mid);
}

sub movie_panic_while_waiting {
    my ($err_file, $mid) = @_;
    movie_panic($err_file, $mid);
    remove_wait_label($mid);
}

sub movie_panic {
    my ($err_file, $mid) = @_;
    my $err = read_file($err_file);
    if ($err and $err =~ /\S/ and $err !~ /^\s*Terminated\s*$/s) {
        err "Can't get movie: $err";
    }

    # no warn -- object might already have been deleted.
    download_stopped($mid, 1);
}

sub profile_dialog {
    my ($profiles) = @_;
    
    # name => dir
    my %profiles = %$profiles;

    #Gtk2::Gdk::Threads->enter;
    my $dialog = make_dialog();

    my $id_col = 0;

    my $model = Gtk2::ListStore->new ('Glib::String');
    for (keys %profiles) {
        # iter, col, val
        $model->set ($model->append, $id_col, $_);
    }
    my $combo_box = Gtk2::ComboBox->new ($model);

    # to display anything, you must pack cell renderers into
    # the combobox, which implements the Gtk2::CellLayout interface.
    my $renderer = Gtk2::CellRendererText->new;
    $combo_box->pack_start ($renderer, 0);
    $combo_box->add_attribute ($renderer, text => $id_col);

    $combo_box->set_active(0);

    $dialog->set_size_request(300, -1);
    my $ca = $dialog->get_content_area;

    my $fr = Gtk2::Frame->new;

    my $hb = Gtk2::HBox->new;
    my $vb = Gtk2::VBox->new(0);

    $fr->add($hb);
    $ca->add($fr);
    $hb->pack_start($vb, 1, 0, 10);

    my $l = Gtk2::Label->new;
    $l->set_label("Choose profile:");
    $vb->pack_start($l, 1, 0, 10);
    $vb->pack_start($combo_box, 0, 0, 10);

    my $al = Gtk2::Alignment->new(0,0,0,0);
    my $ok = Gtk2::Button->new_from_stock('gtk-ok');
    $al->add($ok);
    $dialog->get_action_area->add($al);
    $dialog->show_all;

    my $response;

    $ok->signal_connect('clicked', sub {
        my ($self, $blah) = @_;
        $response = $profiles{$combo_box->get_active_text} or warn;
        $dialog->destroy;
    });

        $dialog->run;

        #Gtk2::Gdk::Threads->leave;
    return $response;
}

sub output_dir_dialog {

    my $d = Gtk2::FileChooserDialog->new("Choose output directory", $w,
        'select-folder',
        'gtk-ok' => 'accept',
    );

    {
        my $t = '/tmp';
        -e $t and -d $t and $d->set_current_folder($t);
    }
    my $od;
    $d->signal_connect('response', sub {
        my ($self, $res) = @_;
        if ($res eq 'accept') {
            $od = $d->get_filename or die;
            #D $od;
            $d->destroy;
        }
        else {
            $d->run;
        }
    });
    $d->run;

    return $od;
}


sub do_output_dir_dialog {
    my $od;
    while (!$od) {
        my $o = output_dir_dialog();
        $od = $o if main::check_output_dir($o);
    }
    set_output_dir($od);
    # doesn't work
    #$status_bar->remove_all(STATUS_OD);
    $status_bar->pop(STATUS_OD);
}

sub set_output_dir {
    my ($od) = @_;
    $output_dir = $od;
    main::set_output_dir($output_dir);

    timeout(100, sub {
            #Gtk2::Gdk::Threads->enter;
        $status_bar_dir or return 1;
        set_label($status_bar_dir, "$OUTPUT_DIR_TXT $output_dir", { size => 'small' });
        #Gtk2::Gdk::Threads->leave;
        0;
    });
}

sub set_cursor_timeout {
    my ($widget, $curs) = @_;
    timeout(50, sub {
        if (my $w = $widget->window) {
            $w->set_cursor(Gtk2::Gdk::Cursor->new($curs));
            return 0;
        }
        1;
    });
}

1;
