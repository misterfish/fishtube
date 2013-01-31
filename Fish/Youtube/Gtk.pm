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

use Time::HiRes 'sleep';

use File::stat;
use File::Basename;

use Math::Trig ':pi';

use Fish::Gtk2::Label;
my $L = 'Fish::Gtk2::Label';

use Fish::Youtube::Utility;
use Fish::Youtube::Download;
use Fish::Youtube::Anarchy;

my $D = 'Fish::Youtube::Download';

#%

# make up a unique id
use constant STATUS_OD => 100;
use constant STATUS_MISC => 101;

sub timeout;

sub err;
sub error;
sub war;
sub mess;
sub max;

my $IMAGES_DIR = $main::bin_dir . '/../images';

-d $IMAGES_DIR or error "Images dir", Y $IMAGES_DIR, "doesn't exist.";
-r $IMAGES_DIR or error "Images dir", Y $IMAGES_DIR, "not readable";

my %IMG = (
    add                 => 'add-12.png',
    cancel              => 'cancel-20.png',
    cancel_hover        => 'cancel-20-hover.png',
);

my $HEIGHT = 300;

my $WID_PERC = .75;

my $WP = 50;
my $HP = 50;

my $RIGHT_SPACING_H_1 = 10;
my $RIGHT_SPACING_H_2 = 10;
my $RIGHT_PADDING_TOP = 20;

# start watching when this perc downloaded.
my $AUTO_WATCH_PERC = 10;
my $auto_start_watching = 1;

my $RIGHT_SPACING_V = 15;

# separation proportion
my $PROP = .5;

my $STATUS_PROP = .7;

my $SCROLL_TO_TOP_ON_ADD = 1;

my $OUTPUT_DIR_TXT = "Output dir:";

my $INFO_X = $WP + $RIGHT_SPACING_H_1 + $RIGHT_SPACING_H_2;

my $Scrollarea_height = $RIGHT_PADDING_TOP;

# o() creates anonymous objects with -> accessors
# hashes have:
# set: $obj->h($k, $v)
# get: $obj->h($k)
# delete: $obj->delete_h($k)
# $obj->h_keys, $obj->h_values

my $W_sw = o(
    left => Gtk2::ScrolledWindow->new,
    right => Gtk2::ScrolledWindow->new,
);

my $W_hp = o(
    main => Gtk2::HPaned->new,
    main_pos => undef,
);

my $W_im = o(
    #prog => Gtk2::Image->new,
);

my $W_sl = o(
    # is a Treeview
    hist => Gtk2::SimpleList->new ( 
        ''    => 'text',
    ),
);

my $W_ly = o(
    right => Gtk2::Layout->new,
);

my $W_lb = o(
    od => Fish::Gtk2::Label->new,
);

my $W_sb = o(
    main => Gtk2::Statusbar->new,
);

my $tree_data_magic;

my $W;

my $Output_dir;

my $G = o(

    # inited then calculated
    height => $HEIGHT,
    # calculated
    width => -1,

    init => 0,
    last_mid_in_statusbar => -1,

    # two ways to use hashes, bit different syntax
    '%img' => {},
    '%download_buf' => {},
    # mid => text
    is_waiting => {},

    # mid => [
    # 0 cur_size
    # 1 '/'
    # ]
    size_label => {},

    info_box => {},
    cancel_images => {},
    auto_launched => {},
    download_successful => {},

    movies_buf => [],
    # left pane
    movie_data => [],

);

my $Col = o(
    white => get_color(255,255,255,255),
    black => get_color(0,0,0,255),
);


{
    my %img = map {

        my $i = "$IMAGES_DIR/$IMG{$_}";
        -r $i or error "Image", Y $i, "doesn't exist or not readable.";

        $_ => $i,

    } qw/ add cancel cancel_hover /;

    $G->img(\%img);
}

my $Last_mid = -1;
my $Last_idx = -1;

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

    $W = Gtk2::Window->new('toplevel');

    my $scr = $W->get_screen;
    my $wid = $scr->get_width;
    if (! $wid) {
        warn "couldn't get screen width";
        $G->width(800);
    }
    else {
        $G->width($wid * $WID_PERC);
    }

    $W->set_default_size($G->width, $G->height);
    $W->modify_bg('normal', $Col->white);

    $W->signal_connect('configure_event', \&configure_main );
    $W->signal_connect('destroy', sub { $W->destroy; exit 0 } );

    my $l = Gtk2::VBox->new;
    
    my $l_buttons = Gtk2::HBox->new;

    $l->pack_start($l_buttons, 0, 0, 10);

    my $lwf = Gtk2::Frame->new;
    $lwf->add($W_sw->left);
    $l->add($lwf);

    my $button_add = Gtk2::EventBox->new;
    $button_add->add(Gtk2::Image->new_from_file($G->img('add')));
    $button_add->signal_connect('button-press-event', sub {
        my $response = inject_movie();
    });
    $button_add->modify_bg('normal', $Col->white);

    set_cursor_timeout($button_add, 'hand2');

    $l_buttons->pack_start($button_add, 0, 0, 10);

    $W_sw->left->set_policy('never', 'automatic');

    $W_sl->hist->set_headers_visible(0);

    $W_sw->left->add($W_sl->hist);
    $W_sw->left->show_all;

    # tree_data_magic is tied
    $tree_data_magic = $W_sl->hist->{data};

    $W_sl->hist->signal_connect (row_activated => sub { row_activated(@_) });

    set_pane_position($G->width);

    my $outer_box = Gtk2::VBox->new;

    # want to flush label right but doesn't work
    my $status_bar_dir_box = Gtk2::EventBox->new;
    $status_bar_dir_box->modify_bg('normal', $Col->white);

    $status_bar_dir_box->add($W_lb->od);
    set_cursor_timeout($status_bar_dir_box, 'hand2');

    $status_bar_dir_box->signal_connect('button-press-event', sub {
        do_output_dir_dialog();
    });

    $W_lb->od->modify_bg('normal', $Col->black);

    # expand, fill, padding
    # fill has no effect if expand is 0.
    $outer_box->pack_start($W_hp->main, 1, 1, 0);

    $W_lb->od->set_label("$OUTPUT_DIR_TXT", { size => 'small', color => 'red'});

    my $auto_start_cb = Gtk2::CheckButton->new('');
    $auto_start_cb->set_active(1);
    $auto_start_cb->signal_connect('toggled', sub {
        state $state = 1;
        $state = !$state;
        $auto_start_watching = $state;
    });
    {
        my $l = ($auto_start_cb->get_children)[0];
        $L->set_label($l, "Auto start ($AUTO_WATCH_PERC%)", { size => 'small' });
    }
    my $status_bar_right_hbox = Gtk2::HBox->new(0);
    $status_bar_right_hbox->pack_start($auto_start_cb, 0, 0, 10);
    $status_bar_right_hbox->pack_start($status_bar_dir_box, 0, 0, 10);

    # row, col, homog
    my $status_table = Gtk2::Table->new(1, 2, 0);
    # leftmost col, rightmost col, uppermost row, lower row, optx, opty, padx, pay
    my $oo = [qw/ expand shrink fill /];
    my $ooo = 'shrink';
    $status_table->attach($W_sb->main, 0, 1, 0, 1, $ooo, $ooo, 10, 10);
    $status_table->attach($status_bar_right_hbox, 1, 2, 0, 1, $ooo, $ooo, 10, 10);

    $W_sb->main->set_size_request($G->width * .7, -1);

    $W_lb->od->set_size_request($G->width * .3, -1);

    $W_sb->main->set_has_resize_grip(0);

    $outer_box->pack_end($status_table, 0, 0, 10);

    {
        my $b = Gtk2::Button->new('a');
        $b->signal_connect('clicked', sub {
                # some debug
            });
        #$outer_box->add($b);
    }

    $W->add($outer_box);

    $W_sw->right->set_policy('never', 'automatic');

    $W_hp->main->child2_shrink(1);

    $W_hp->main->pack1($l, 0, 1);

    $W_ly->right->signal_connect('expose_event', \&expose_drawable );
    $W_ly->right->modify_bg('normal', $Col->white);

    $W_sw->right->add($W_ly->right);

    $W_hp->main->pack2($W_sw->right, 0, 1);

    $W->show_all;

    $W->set_app_paintable(1);

    # why ever set to 0?
    #$w->set_double_buffered(0);

    # pane moved
    $W_hp->main->get_child1->signal_connect('size_allocate', sub { 
        $W_hp->main_pos( $W_hp->main->get_position );
        redraw();
    });

    timeout(50, sub {

            if ($D->is_anything_drawing) {
                redraw();
            }
        1;
    });

    timeout(1000, sub { 
        update_movie_tree() ;
    });


my $SIMULATE = 0;

    $SIMULATE and simulate();

    my @init_chain;

    if ($profile_ask) {
        push @init_chain, sub {
            my $pd = profile_dialog($profile_ask);
            main::set_profile_dir($pd);
        };
    }

    push @init_chain, sub { $G->init(1) };

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
    return $G->init;
}

sub set_buf {
    my ($class, $_movies_buf) = @_;
    #@Movies_buf: latest in front
    unshift_r $G->movies_buf, $_ for reverse @$_movies_buf;
}

sub update_movie_tree {

    state $last;
    state $first = 1;

    my $i = 0;

    $G->movies_buf or return 1;

    # single value of {} means History returned exactly 0 entries
    {
        my $m = shift_r $G->movies_buf;
        if (! %$m) {
            @$tree_data_magic = "No movies -- first browse somewhere in Firefox.";
            return 1;
        }
        else {
            unshift_r $G->movies_buf, $m;
        }
    }

    if ($first) {
        @$tree_data_magic = ();
        $first = 0;
    }

    #@Movies_buf: latest in front

    my @m = list $G->movies_buf;
    $G->movies_buf([]);

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

    my $num_in_tree_before_add = tree_num_children($W_sl->hist);

    for (reverse @n) {
        my ($u, $t) = ($_->{url}, $_->{title});

        $t =~ s/ \s* - \s* youtube \s* $//xi;

        $Last_mid++;
        unshift @$tree_data_magic, $t;
        unshift_r $G->movie_data, { mid => $Last_mid, url => $u, title => $t};

        # first in buffer is last
        $last = $u if ++$i == @n;
    }

    if (@n and $SCROLL_TO_TOP_ON_ADD) {
        # necessary? seems there could be a lag when adding to tied tree
        # magic.
        timeout 50, sub {
            if (tree_num_children($W_sl->hist) != $num_in_tree_before_add) {
                $W_sw->left->get_vscrollbar->set_value(0);
                return 0;
            }
            1;
        };
    }

    1;
}

sub tree_num_children {
    my $treeview = shift;
    return $treeview->get_model->iter_n_children;
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

    my $row_idx = $path->get_indices;
    my $d = $G->movie_data->[$row_idx] or die;
    my ($u, $t, $mid) = ($d->{url}, $d->{title}, $d->{mid});

    start_download($u, $t, $mid);
}

sub start_download {
    my ($u, $t, $mid) = @_;

    # already downloaded
    return if $D->exists($mid);
    
    if (! $Output_dir) {
        # remove_all doesn't seem to work.
        $W_sb->main->pop(STATUS_OD);
        $W_sb->main->push(STATUS_OD, 'Choose output dir first.');
        return;
    }

    $G->download_successful->{$mid} = 0;
    $G->auto_launched->{$mid} = 0;

    my $box;

    my $tmp = main::get_tmp_dir();

    my $wait_s = "Trying to get '";
    $wait_s .= $t ? $t : 'manual download';
    $wait_s .= "' ";
    $G->is_waiting->{$mid} = $wait_s;

    $G->last_mid_in_statusbar($mid);
    $W_sb->main->push($mid, $wait_s);

    state $first = 1;

    my $manual;
    my $of;

    my $force_get;

    # manual download -- get name from youtube-get
    if (! $t) {
        $manual = 1;

        # overwrite if exists
        $force_get = 1;
    } 
    
    else {
        $t =~ s/^\s+//;
        $t =~ s/\s+$//;

        $t =~ s/[\n:!\*<>\`\$]//g;

        $t =~ s|/|-|g;
        $t =~ s|\\|-|g;
        $t =~ s/"/'/g;

        $of = "$Output_dir/$t.flv";

        if (-r $of) {
            my $dialog = Gtk2::MessageDialog->new ($W,
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
        return 0 unless $G->last_mid_in_statusbar == $mid;
        return 0 unless $text = $G->is_waiting->{$mid};

        $text .= '.';
        $W_sb->main->pop($mid);
        $W_sb->main->push($mid, $text);
        $G->is_waiting->{$mid} = $text;
        1;
    });

    $W_ly->right->show_all;

    if ($first) {
        set_pane_position($G->width / 2);
        $first = 0;
    }

    # make some of these vars internal to main todo
    my ($pid, $err_file) = main::start_download($mid, $u, ($manual ? undef : $of), $tmp, $Output_dir, $force_get);

    if (!$pid) {
        # subproc failed.
        movie_panic_while_waiting($err_file, $mid);
        return;
    }

    my $i = 0;

    my $try = 0;
    # wait for forked proc to tell us something.
    timeout(2000, sub {
        $i++ > 20 and error "youtube-get behaving strange.";

        my ($name, $size);
        # aborted or finished very fast
        if (! main::process_running($pid)) {
            ($name, $size) = get_metadata("$tmp/.yt-file");

            if (!$name) {
                # could still be waiting for fh from child to flush. wait
                # another two seconds ...
                if (++$try == 2) {
                    war "sdChild died", Y $pid;
                    movie_panic_while_waiting($err_file, $mid);
                    return 0;
                }
                return 1;
            }
            else {
                # ok
            }
        }
        # still running
        else {
            ($name, $size) = get_metadata("$tmp/.yt-file");
            # keep waiting
            return 1 unless $name;
        }

        # got it, add download and kill timeout

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
            return file_progress({ simulate => 0}, $mid, $o, $size, $err_file, $pid);
        });

        return 0;
    });
    # / child wait
}

sub get_metadata {
    my ($file) = @_;

    my ($s, $code) = sys qq, cat 2>/dev/null $file,, 0;
    
    my ($name, $size);

    if ($s =~ /(.+)\n(\d+)/) {

        # got name and size from forked proc. can officially start download.
       
        ($name, $size) = ($1, $2);
        return ($name, $size);
    }
    else {
        D2 'no meta';
    }

    return;
}

sub file_progress {
    my $simulate;
    if (ref $_[0] eq 'HASH') {
        my $opt = shift;
        $simulate = $opt->{simulate} // 0;
    }
    my ($mid, $file, $size, $err_file, $pid) = @_;
    my $s = stat $file or warn(), return 1;

    my $d = $D->get($mid);

    # download object destroyed for some reason
    if (! $d and ! $simulate) {
        movie_panic($err_file, $mid);
        return 0;
    }

    my $cur_size = $s->size;
    $d->prog($cur_size);

    if (!$G->auto_launched->{$mid} and ! $simulate ) {
        if ($auto_start_watching and $cur_size / $size * 100 > $AUTO_WATCH_PERC) {
            $G->auto_launched->{$mid} = 1;
            main::watch_movie($file);
        }
    }

    # process not running -- finished or aborted

    # ps, heavy?

    if ( ! sys_ok "ps $pid" and ! $simulate ) {

        D2 'cur_size', $cur_size;

        # finished
        if ($cur_size == $size) {
            download_finished($mid);
            return 0;
        }

        # cancelled / other problem
        else {
            movie_panic($err_file, $mid);
            return 0;
        }
    }

    # still downloading
    return 1;
}

sub add_download {

    my ($mid, $title, $size, $of, $pid) = @_;

    # downloads added faster than poll_downloads can grab them (shouldn't
    # happen)
    warn "download buf not empty" if $G->download_buf;

    $G->download_buf({
        idx => ++$Last_idx,
        mid => $mid,
        size => $size,
        title => $title,
        of => $of,
        pid => $pid,
    });
}

sub poll_downloads {

    my %db = $G->download_buf or return 1;

    # start new download

    my $size = $db{size};
    my $title = $db{title};
    my $idx = $db{idx};
    my $of = $db{of};
    my $pid = $db{pid};

    my $pixmap = make_pixmap();
    clear_pixmap($pixmap);

    my $mid = $db{mid};

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

    $G->download_buf({});

    my $anarchy = Fish::Youtube::Anarchy->new(
        width => $WP,
        height => $HP,
    );

    my $hb = Gtk2::HBox->new;
    my $vb = Gtk2::VBox->new;
    my $eb = Gtk2::EventBox->new;

    my $c1 = $Col->black;
    my $c2 = get_color(100,100,33,255);
    my $c3 = $c2;
    my $c4 = $c1;

    my $l1 = $L->new($title, { size => 'small' });
    $l1->modify_fg('normal', $c1);

    my $l2 = $L->new;
    $l2->modify_fg('normal', $c2);
    $G->size_label->{$mid}[0] = $l2;

    my $l3 = $L->new('/', { size => 'small' });
    $l3->modify_fg('normal', $c3);
    $G->size_label->{$mid}[1] = $l3;

    my $l4 = $L->new(nice_bytes_join $size, { size => 'small' });
    $l4->modify_fg('normal', $c4);

    my $im = Gtk2::Image->new;

    my $pix_normal = Gtk2::Gdk::Pixbuf->new_from_file($G->img('cancel'));
    my $pix_hover = Gtk2::Gdk::Pixbuf->new_from_file($G->img('cancel_hover'));
    $im->set_from_pixbuf($pix_normal);

    my $eb_im = Gtk2::EventBox->new;
    $eb_im->add($im);
    $eb_im->modify_bg('normal', $Col->black);
    $im->modify_bg('normal', $Col->black);

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

    $_->modify_bg('normal', $Col->white) for $l1, $l2, $l3, $l4, $vb, $eb, $hb, $eb_im;

    $G->info_box->{$mid} = $eb;

    $eb->add($vb);

    remove_wait_label($mid);

    $W_ly->right->put($eb, $INFO_X, $RIGHT_PADDING_TOP + $idx * ($HP + $RIGHT_SPACING_V));

    $eb->signal_connect('button-press-event', sub {
        main::watch_movie($of);
    });

    update_scroll_area(+1);
    $W_ly->right->show_all;

    set_cursor_timeout($G->info_box->{$mid}, 'hand2');

    $G->cancel_images->{$mid} = $im;

    $eb_im->signal_connect('button-press-event', sub {
        cancel_download($mid);
        # 1 means don't propagate (we are inside $eb)
        return 1;
    });

    # check size, update download status, update pixmap
    timeout(50, sub {

        my $d = $D->get($mid) or do { 
            D2 'stopping animation: download obj destroyed';
            return 0;
        };
        $d->is_drawing or do {
            D2 'stopping animation: is_drawing is 0';
            return 0;
        };

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

        my $l = $G->size_label->{$mid}[0];
        $l and $l->set_label(nice_bytes_join $p, { size => 'small' });

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

            D2 'animation loop: completed, stopping';

            draw_surface_on_pixmap($pixmap, $surface);

            # manually call one last redraw
            redraw();
            
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
        return if $ew == $G->width and $eh == $G->height;
        #D 'configuring', 'width', $ew, 'height', $eh;
    }

    $G->width($ew);
    $G->height($eh);

    # make new pixmaps for all current downloads
    $D->make_pixmaps;

}

sub make_pixmap {
    my ($pw, $ph) = ($WP, $HP);
    my $pixmap = Gtk2::Gdk::Pixmap->new($W->window, $pw, $ph, 24);
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
    $_->destroy, undef $_ for $G->cancel_images->{$mid}, list $G->size_label->{$mid};
    $G->download_successful->{$mid} = 1;
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

    $Last_idx--;
    # decrease idx of later dls by 1
    for my $d ($D->all) {
        my $j = $d->idx;
        if ($j > $idx) {
            $d->idx_dec;
            my $box = $G->info_box->{$d->id};
            # shift up
            $W_ly->right->move($box, $INFO_X, $RIGHT_PADDING_TOP + $d->idx * ($HP + $RIGHT_SPACING_V));
        }
    }
    my $ib = delete $G->info_box->{$mid};
    $ib->destroy;

    update_scroll_area(-1);
}

sub err {
    my ($a, $b) = @_;

    #Gtk2::Gdk::Threads->enter;

    # class method or not
    my $s = $b // $a;

    my $dialog = Gtk2::MessageDialog->new ($W,
        'modal',
        'error',
        'close',
    $s);

    $dialog->signal_connect('response', sub { shift->destroy });
    
    $dialog->run;

    #Gtk2::Gdk::Threads->leave;
}

sub status {
    my ($class, $s) = @_;
    $G->init or warn, return;
    $W_sb->main->push(STATUS_MISC, $s);
}

sub mess {
    my ($a, $b) = @_;

    # class method or not
    my $s = $b // $a;

    my $d = Gtk2::MessageDialog->new($W,
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
    $W_ly->right->set_size(2000, $Scrollarea_height);
}

sub set_pane_position {
    my ($p) = @_;
    $W_hp->main_pos($p);
    $W_hp->main->set_position($p);
}

sub inject_movie {
    my $url = inject_movie_dialog() or return;
    state $i = 0;
    # check url?
    $Last_mid++;
    #start_download($url, 'manual ' . ++$i, $Last_mid);
    start_download($url, undef, $Last_mid);
}

sub make_dialog {
    my $win = shift;

    my $wi = $win // $W;

    my $dialog = Gtk2::Dialog->new;

    $dialog->set_transient_for($wi);
    $dialog->set_position('center-on-parent');
    return $dialog;
}

sub inject_movie_dialog {
    my $dialog = make_dialog();
    my $c = $dialog->get_content_area;
    my $a = $dialog->get_action_area;

    my $l = $L->new('Manually add URL');
    $c->add($l);

    my $i = Gtk2::Entry->new;
    #$i->set_max_length(80);
    $i->set_size_request(int $G->width / 2,-1);


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
    $G->is_waiting->{$mid} = 0;
    $W_sb->main->pop($mid);
}

sub movie_panic_while_waiting {
    my ($err_file, $mid) = @_;
    movie_panic($err_file, $mid);
    remove_wait_label($mid);
}

sub movie_panic {
    my ($err_file, $mid) = @_;
    my $fh = safeopen $err_file;
    local $/ = undef;
    my $err = <$fh>;
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

    my $l = $L->new("Choose profile:");
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

    my $d = Gtk2::FileChooserDialog->new("Choose output directory", $W,
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
    $W_sb->main->pop(STATUS_OD);
}

sub set_output_dir {
    my ($od) = @_;
    $Output_dir = $od;
    main::set_output_dir($Output_dir);

    timeout(100, sub {
        $W_lb->od or return 1;
        $W_lb->od->set_label("$OUTPUT_DIR_TXT $Output_dir", { size => 'small' });
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
sub simulate {
    my $SIM_TMP = main::get_tmp_dir();
    my $sim_idx = 0;
    set_pane_position($G->width / 2);
    timeout(1000, sub {
        ++$Last_mid;
        my $mid = $Last_mid;
        my $size = int rand 1e6;
        my $of = "$SIM_TMP/blah$mid.flv";
        my $err_file = 'null';
        my $pid = -1234;
        add_download($mid, $of, $size, $err_file, $pid);

        my $fh = safeopen ">$of";
        select $fh;
        $| = 1;
        select STDOUT;

        my $cur_size = 0;
        my $bytes = int ($size / 30);
        timeout(100, sub {
            if ($size - $cur_size < $bytes) {
                print $fh '1' x ($size - $cur_size);
                return 0;
            }
            else {
                print $fh '1' x $bytes;
                $cur_size += $bytes;
            }
        });

        timeout( 200, sub { 
            return file_progress({ simulate => 1}, $mid, $of, $size, $err_file, $pid);
        });

        return ++$sim_idx == 10 ? 0 : 1;
    });
}

sub redraw {
    # And all children.
    $W->queue_draw;
}


1;
