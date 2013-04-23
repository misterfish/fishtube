package Fish::Youtube::Gtk;

use 5.10.0;

use strict;
use warnings;

use threads;
use threads::shared;

use Gtk2 qw/ -init -threads-init /;
use Gtk2::SimpleList;

use Gtk2::Pango;

die "Glib::Object thread safety failed" unless Glib::Object->set_threadsafe (1);

use AnyEvent;
use AnyEvent::HTTP;

use Time::HiRes 'time';

use File::stat;
use File::Basename;

use Fish::Gtk2::Label;
my $L = 'Fish::Gtk2::Label';

use Fish::Youtube::Utility;

use Fish::Youtube::Download;

use Fish::Youtube::Components::Anarchy;
use Fish::Youtube::Components::Download;
use Fish::Youtube::Components::MoviesList;

use Fish::Youtube::Get;

my $D = 'Fish::Youtube::Download';

# make up a unique id
use constant STATUS_OD => 100;
use constant STATUS_MISC => 101;

# not implemented.
use constant ALLOW_SYNC => 0;

sub err;
sub error;
sub war;
sub mess;
sub max;

my $HIDING;

my $IMAGES_DIR = $main::bin_dir . '/../images';
my $RC_DIR = $main::bin_dir . '/../rc';

-d $IMAGES_DIR or error "Images dir", Y $IMAGES_DIR, "doesn't exist.";
-r $IMAGES_DIR or error "Images dir", Y $IMAGES_DIR, "not readable";

my $TIMEOUT_METADATA = 15000;
#my $TIMEOUT_REDRAW = 50;
my $TIMEOUT_REDRAW = 100;

my $DELAY_START_DOWNLOAD = 300;

my %IMG = (
    add                 => 'add-12.png',
    cancel              => 'cancel-17.png',
    cancel_hover        => 'cancel-17-hover.png',
    delete              => 'trash-14.png',
    delete_hover        => 'trash-14-hover.png',
    blank               => 'blank-17.png',
);

my $HEIGHT = 300;

my $WID_PERC = .75;

my $WP = Fish::Youtube::Components::Download->width;
my $HP = Fish::Youtube::Components::Download->height;

my $RIGHT_SPACING_H_1 = 10;
my $RIGHT_SPACING_H_2 = 10;
my $RIGHT_PADDING_TOP = 20;

# start watching when this perc downloaded.
my $AUTO_WATCH_PERC = 10;

my $RIGHT_SPACING_V = 15;

# separation proportion
my $PROP = .5;

my $STATUS_PROP = .7;

my $T = o(
    output_dir => "Output dir:",
    pq1  => "Quality:",
    pq2  => "Preferred quality:",
    pq3  => "Required quality:",
    pt1  => "Format:",
    pt2  => "Preferred format:",
    pt3  => "Required format:",
    fb  => "Allow fallback",
    overwrite => 'Existing files will be overwritten.',
    ask => "(ask)",
);

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

my $W_eb = o(
    pref_q_and_t        => Gtk2::EventBox->new,
    od          => Gtk2::EventBox->new,
);

my $W_ly = o(
    right => Gtk2::Layout->new,
);

my $W_lb = o(
    od => Fish::Gtk2::Label->new,
    pq => Fish::Gtk2::Label->new,
    pt => Fish::Gtk2::Label->new,
);

my $W_sb = o(
    main => Gtk2::Statusbar->new,
);

my $W_tb = o(
    # row, col, homog
    options => Gtk2::Table->new(2,3,0),
);

my $W;

my $Output_dir;

#globals

my $G = o(

    height => $HEIGHT, # inited then calculated
    width => -1, # calculated

    # for prog
    stats => {},

    auto_start_watching => 1,

    init => 0,
    last_mid_in_statusbar => -1,

    # other way to use hash.
    '%img' => {},

    download_comp => {},
    movies_list_comp => undef,

    # auto add methods last_xxx_inc, last_xxx_dec.
    '+-last_mid' => -1,
    '+-last_idx' => -1,

    # medium
    preferred_quality => 1,
    # mp4
    preferred_type => 0,

    qualities => ALLOW_SYNC ? 
        [ Fish::Youtube::Get->qualities ] :
        [ Fish::Youtube::Get->qualities, $T->ask ],

    types => ALLOW_SYNC ? 
        [ Fish::Youtube::Get->types ] :
        [ Fish::Youtube::Get->types, $T->ask ],

    is_tolerant_about_quality => 1,
    is_tolerant_about_type => 1,

);

my $Col = o(
    white => get_color(255,255,255,255),
    black => get_color(0,0,0,255),
);

sub col { $Col }

{
    my %img = map {

        my $i = "$IMAGES_DIR/$IMG{$_}";
        -r $i or error "Image", Y $i, "doesn't exist or not readable.";

        $_ => $i,

    } keys %IMG;

    $G->img(\%img);
}

sub init {

    Gtk2::Gdk::Threads->enter;

    my ($class, $od, $opt) = @_;
    $opt //= {};

    my $rc_file = "$RC_DIR/gtkrc";
    if (! -e $rc_file) {
        war "Can't open rc file:", $rc_file;
    }
    else {
        # Don't know if successful.
        # Status bar should be 'smooth'.
        Gtk2::Rc->parse($rc_file);
    }

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
    
    my $l_buttons = Gtk2::VBox->new;

    my $lwf = Gtk2::Frame->new;
    $lwf->add($W_sw->left);
    $l->add($lwf);

    $W_eb->$_->modify_bg('normal', $Col->white) for keys %$W_eb;

    my $button_add = Gtk2::EventBox->new;
    $button_add->add(Gtk2::Image->new_from_file($G->img('add')));
    $button_add->signal_connect('button-press-event', sub {
        my $response = inject_movie();
    });

    $button_add->modify_bg('normal', $Col->white);
    set_cursor_timeout($button_add, 'hand2');

    $l_buttons->pack_start($button_add, 0, 0, 10);

    $W_sw->left->set_policy('never', 'automatic');

    {
        my $movies_list = Fish::Youtube::Components::MoviesList->new(
            profile_dir => main->profile_dir,
            cb_row_activated => \&row_activated,
        );

        my $tree = $movies_list->widget;
        $G->movies_list_comp($movies_list);
        $W_sw->left->add($tree);
    }

    $W_sw->left->show_all;

    set_pane_position($G->width);

    my $outer_box = Gtk2::VBox->new;

    {
        my $b = $W_eb->od;

        $b->add($W_lb->od);
        set_cursor_timeout($b, 'hand2');

        $b->signal_connect('button-press-event', sub {
            do_output_dir_dialog();
        });
    }

    {
        my $eb = $W_eb->pref_q_and_t;
        my $vb = Gtk2::VBox->new;
        {
            my $al = Gtk2::Alignment->new(0,0,0,0);
            $al->add($W_lb->pq);
            $vb->add($al);
        }
        {
            my $al = Gtk2::Alignment->new(0,0,0,0);
            $al->add($W_lb->pt);
            $vb->add($al);
        }
        $eb->add($vb);
        set_cursor_timeout($eb, 'hand2');
        $eb->signal_connect('button-press-event', sub {
            get_q_and_t_dialog();
            set_pref_labels();
        });
    }

    $W_lb->od->modify_bg('normal', $Col->black);

    {
        my $f = Gtk2::Frame->new;
        $outer_box->pack_start($f, 1, 1, 0);
        $f->add($W_hp->main);
    }

    $W_lb->od->set_label($T->output_dir, { size => 'small', color => 'red'});

    set_pref_labels();

    my $oo = [qw/ expand shrink fill /];
    my $ooo = 'fill';

    {
        my $auto_start_cb = Gtk2::CheckButton->new('');
        $auto_start_cb->set_active(1);
        $auto_start_cb->signal_connect('toggled', sub {
            state $state = 1;
            $state = !$state;
            $G->auto_start_watching($state);
        });
        {
            my $l = ($auto_start_cb->get_children)[0];
            $L->set_label($l, "Auto start ($AUTO_WATCH_PERC%)", { size => 'small' });
        }

        my $t = $W_tb->options;

        # leftmost col, rightmost col, uppermost row, lower row, optx, opty, padx, pay

        $t->attach($W_sb->main, 0, 1, 1, 2, $ooo, $ooo, 10, 10);

        $t->attach(left($auto_start_cb), 1, 2, 0, 1, $ooo, $ooo, 10, 10);
        $t->attach($W_eb->od, 2, 3, 1, 2, $ooo, $ooo, 10, 10);

        my $vb = Gtk2::VBox->new;
        $vb->add($W_eb->pref_q_and_t);
        $t->attach($vb, 1, 2, 1, 2, $ooo, $ooo, 10, 10);

        $outer_box->pack_end($t, 0, 0, 10);
    }

    $W_sb->main->set_size_request($G->width * .7, -1);

    $W_lb->od->set_size_request($G->width * .3, -1);

    $W_sb->main->set_has_resize_grip(0);

    if (0) {
        my $b = Gtk2::Button->new('a');
        $b->signal_connect('clicked', sub {

        my $s = $W_sw->right->get_vscrollbar;
        D 'doing';
        $s->set_inverted(1);
        $s->set_value(0);

        });

        $outer_box->add($b);
    }

    {
        my $fb = Gtk2::VBox->new;
        my $f = Gtk2::Frame->new;
        $W->add($fb);
        $fb->pack_start($f, 1, 1, 0);
        $f->add($outer_box);
    }

    $W_sw->right->set_policy('never', 'automatic');

    $W_hp->main->child2_shrink(1);

    {

        my $hb = Gtk2::HBox->new(0);
        $hb->pack_start($l_buttons, 0, 0, 4);
        $hb->pack_start($l, 1, 1, 4);
        $W_hp->main->pack1($hb, 0, 1);
    }

    $W_ly->right->signal_connect('expose_event', \&expose_drawable );
    $W_ly->right->modify_bg('normal', $Col->white);

    $W_sw->right->add($W_ly->right);

    {
        my $f = Gtk2::Frame->new;
        my $b = Gtk2::VBox->new;
        # resize, shrink
        $W_hp->main->pack2($b, 0, 1);
        $b->pack_start($W_sw->right, 1, 1, 0);
    }

    $W->show_all;

    $W->set_app_paintable(1);

    # why ever set to 0?
    #$w->set_double_buffered(0);

    # pane moved
    $W_hp->main->get_child1->signal_connect('size_allocate', sub { 
        $W_hp->main_pos( $W_hp->main->get_position );
        redraw();
    });

    timeout $TIMEOUT_REDRAW, sub {
        if ($D->is_anything_drawing) {
            redraw();
        }
        1;
    };

    my @init_chain;

    if ($profile_ask) {
        push @init_chain, sub {
            my $pd = profile_dialog($profile_ask);
            main::set_profile_dir($pd);
        };
    }

    push @init_chain, sub { $G->init(1) };

    my $chain = sub {

        $_->() for @init_chain;
        0;
    };
    timeout 100, $chain;

    # make Y, R, etc. no-ops
    disable_colors();

    # internally releases lock on each iter.
    Gtk2->main;

    Gtk2::Gdk::Threads->leave;
}

sub inited {
    return $G->init;
}

sub get_mid {
    $G->last_mid_inc;
    $G->last_mid;
}

sub row_activated {
    my ($obj, $path, $column) = @_;

    my $row_idx = $path->get_indices;

    my $d = $G->movies_list_comp->get_data($row_idx) or die;

    my ($u, $t, $mid) = ($d->{url}, $d->{title}, $d->{mid});

    my $ok = init_download($u, $t, $mid);

}

sub init_download {
    my ($u, $title, $mid) = @_;

    # already downloaded /-ing
    return if $D->exists($mid);

    if (! $Output_dir) {
        # remove_all doesn't seem to work.
        $W_sb->main->pop(STATUS_OD);
        $W_sb->main->push(STATUS_OD, 'Choose output dir first.');
        return;
    }
    
    set_cursor($W, 'watch');

    $title ||= 'manual download';

    my $download_comp = Fish::Youtube::Components::Download->new(
        title => $title,
        mid => $mid,
    );

    $G->download_comp->{$mid} = $download_comp;

    # main eventbox for comp
    my $download_comp_widget = $download_comp->widget;

    my $height_box = $download_comp->height;

    $G->last_idx_inc;
    my $idx = $G->last_idx;

    # $D class keeps track.

    $D->new(
        # main id = mid
        id      => $mid,

        # id of drawn component in list. 
        # will change when something is deleted.
        idx     => $idx,

        component => $download_comp,
    );

    $W_ly->right->put($download_comp_widget, $INFO_X, $RIGHT_PADDING_TOP + $idx * ($height_box + $RIGHT_SPACING_V));

    update_scroll_area(+1);

    state $first = 1;

    my $manual;

    my $prefq = $G->qualities->[$G->preferred_quality];
    my $preft = $G->types->[$G->preferred_type];
    my $itaq = $G->is_tolerant_about_quality;
    my $itat = $G->is_tolerant_about_type;

    $_ eq $T->ask and $_ = '' for $prefq, $preft;

    D2 'prefq', $prefq, 'preft', $preft;

    my $async = 1;
    $async = 0 unless $prefq && $preft;

    set_cursor($W, 'watch') if ALLOW_SYNC and ! $async;

    # can go
    $W_ly->right->show_all;

    if ($first) {
        set_pane_position($G->width / 2);
        $first = 0;
    }

    redraw();
    timeout 300, sub { normal_cursor $W };

    # Want the redraws to happen immediately, can force render like this.
    timeout $DELAY_START_DOWNLOAD, sub { 
        start_download($mid, $title, $u, $idx, $download_comp, $async, $prefq, $preft, $itaq, $itat);
        return 0;
    }
}

sub start_download {

    my ($mid, $title, $u, $idx, $download_comp, $async, $prefq, $preft, $itaq, $itat) = @_;

    # manual download -- get name from youtube-get
    # if any prompting, we can't know outfile. 
    # also if async, we can't know it.
    # always overwrite if async.

    my $manual;
    $manual = 1 unless $title;

    my $get;
    my $status;
    my $errstr;

    if ($async) {
        ($get, $status, $errstr) = main::start_download_async($u, $Output_dir, $prefq, $preft, $itaq, $itat);
    }
    else {

warn 'not implemented';

        main::start_download_sync($mid, $u, $Output_dir, $prefq, $preft, $itaq, $itat) ;
    }

    if ($status eq 'error') {
        war "Error in download.";
        warn "Errstr: $errstr" if $errstr;

        movie_panic_while_waiting($mid, $errstr);

        return;
    }

    elsif ($status eq 'cancelled') {
        D2 'cancelled.';
        return;
    }

    my $d = $D->get($mid) or warn, return;
    # Get object
    $d->getter($get);
    $d->title($title);

    my $size;

    set_cursor($W, 'x-cursor') unless $async;

    if ($async) {
        # wait for md to get filled.
        my $i = 0;
        my $to = 200;
        timeout $to, sub {
            if ( ++$i > $TIMEOUT_METADATA / $to ) {
                my $w = "Timeout waiting for movie to start."; 
                D $w;
                #err $w;
                movie_panic_while_waiting($mid, $w);
                return;
            }

            if ($size = $get->size) {

                D2 'got size', $size;

                download_started($mid, $title, $get, $size, $manual) ;

                return 0;
            }

            1;
        };
    }
    else {
warn 'not implemented';
        #my $size = $md->{size} or warn, return;
        #my $of = $md->{of} or warn, return;

        #timeout 500, sub { 
        #    download_started($did, $mid, $title, $dl_tracker, $of, $size, $manual) 
        #};
    }
}

# Download really started. Update component, watch size, wait for finish.

sub download_started {
    my ($mid, $title, $get, $size, $manual) = @_;

    my $of = $get->out_file or warn;

    D2 'got md', 'name', $of, 'size', $size;

    if ($manual) {
        $title = basename $of;
        $title =~ s/\.\w+$//;
    }

    my $d = $D->get($mid) or warn, return;

    my $download_comp = $G->download_comp->{$mid} or warn, return;
    $download_comp->started(
        file_size => $size,
        cb_watch_movie => sub {
            main::watch_movie($of);
        },
        cb_delete_file => sub {
            $of or return;
            main::delete_file($of) or return;
            # remove_download_entry called through timeout somewhere.
            #remove_download_entry($mid);
        },
    );

    $d->size($size);

    my $size_set = 0;

    # check size, update download status, update component.
    timeout(50, sub {

        # Don't check is_downloading here, will end too early.

        $d->is_drawing or do {
            D2 'stopping animation: is_drawing is 0';
            return 0;
        };

        state $last = -1;

        if (!$size_set) {
            $size // return 1;
            $download_comp->file_size($size);
            $size_set = 1;
        }

        my $err;

        my $p = $d->prog;
        if (not defined $p) {
            D2 "p not defined (yet)";
            return 1;
        }

        if ($download_comp->update($p)) {
            return 1;
        }
        else {
            # manually call one last redraw
            redraw();
            $d->stopped_drawing;
            return 0;
        }

    });

    my $cur_size = 0;

    # update $cur_size and also set ->prog of download object. 
    # cur_size is a bit useless.
    timeout 200, sub { 

        # file_progress is where we see if download finished.
        return file_progress({ simulate => 0}, $mid, $get, $of, \$cur_size, $size);
    };
    
    timeout 500, sub { auto_start_watching($mid, \$cur_size, $size, $of) };

    D2 'gtk: download started, outer timeout over';
}

sub auto_start_watching {
    my ($mid, $cur_size_r, $size, $file) = @_;

    my $past_thres = $$cur_size_r / $size * 100 > $AUTO_WATCH_PERC;

    if ($past_thres) {
        # box is checked
        if ($G->auto_start_watching) {
            main::watch_movie($file);
        }
        return 0;
    }
    else {
        return 1;
    }
}

sub file_progress {
    my $simulate;
    if (ref $_[0] eq 'HASH') {
        my $opt = shift;
        $simulate = $opt->{simulate} // 0;
    }

    # cur_size_r is watched from outside.
    # nicer if it's set externally to 0 first.
    my ($mid, $get, $file, $cur_size_r, $size) = @_;

    my $d = $D->get($mid);

    if (!$d) {
        D2 'download obj destroyed';
        return;
    }

    my $s = stat $file;

    if (!$s) {
        err "File '$file' disappeared.";
        return;
    }

    my $delete;

    if ($$cur_size_r == 0) {
        $G->stats->{$mid} = {
            start_time => time,
        };
    } 

    my $cs = $s->size;
    $$cur_size_r = $cs unless $cs == -1;

    my $stats = $G->stats->{$mid};
    $stats->{bytes} = $$cur_size_r;

    my $secs = time - $stats->{start_time};

    my $status = $get->{status};
    my $done;

    if ($status eq 'error') {
        my $e;
        war $e if $e = $get->errstr;
        movie_panic($mid, $e);
        return 0;
    }
    elsif ($status eq 'done') {
        $done = 1;
        download_finished($mid);
        warn unless $$cur_size_r == $size;
    }
    elsif ($status eq 'cancelled') {
        D2 'cancelled!';
        remove_download_entry($mid);
        return 0;
    }

    # download object destroyed for some reason

    if (! $d and ! $simulate) {
        movie_panic($mid);
        return 0;
    }

    my $rate = $stats->{bytes} / $secs;
    D2 'Prog:', $$cur_size_r, '/', $size, nice_bytes_join($rate);

    $d->prog($$cur_size_r);

    if ($done) {
        return 0;
    }
    else {
        # should have been flagged done by now.
        warn if $$cur_size_r == $size;
    }

    # still downloading
    return 1;
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
    }

    $G->width($ew);
    $G->height($eh);

    # make new pixmaps for all current downloads
    $D->make_pixmaps;

}

sub make_pixmap {
    shift if $_[0] eq __PACKAGE__;
    my $pw = shift or warn, return;
    my $ph = shift or warn, return; 
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
        my $pixmap = $d->component->pixmap or warn, next;
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
    shift if $_[0] eq __PACKAGE__;
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

    shift if $_[0] eq __PACKAGE__;
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
}

sub cancel_and_remove_download {
    shift if $_[0] eq __PACKAGE__;
    my ($mid) = @_;

    # might have already been destroyed, like if download done.
    if (my $d = $D->get($mid)) {
        my $get = $d->getter;
        download_stopped($mid);
        $get->cancel;
    }
    remove_download_entry($mid);
}

sub remove_download_entry {
    shift if $_[0] eq __PACKAGE__;
    my ($mid) = @_;

    my $d = $D->get($mid) or warn, return;

    my $download_comp;

    $download_comp = $d->component or warn, return;

    my $idx = $d->idx;

    # This will cancel the animation loop (if started). Then we erase the stuff and do
    # one last redraw.
    $d->delete;

    # decrease idx of later dls by 1
    for my $d ($D->all) {
        my $j = $d->idx;
        if ($j > $idx) {
            $d->idx_dec;

            my $box = $d->component->widget;

            # shift up
            $W_ly->right->move($box, $INFO_X, $RIGHT_PADDING_TOP + $d->idx * ($HP + $RIGHT_SPACING_V));
        }
    }
    
    $G->last_idx_dec;
    $download_comp->destroy;

    update_scroll_area(-1);

    #D 'redrawing';
    redraw();
}

sub err {
    my ($a, $b) = @_;

    # class method or not
    my $s = $b // $a;

    my $dialog = Gtk2::MessageDialog->new ($W,
        'modal',
        'error',
        'close',
    $s);

    $dialog->signal_connect('response', sub { shift->destroy });
    
    $dialog->run;
}

sub status {
    my ($class, $s) = @_;
    $G->init or warn, return;
    $W_sb->main->push(STATUS_MISC, $s);
}

sub mess {
    shift if $_[0] eq __PACKAGE__; 
    my ($s) = @_;

    my $d = Gtk2::MessageDialog->new($W,
        'modal',
        'info',
        'ok',
        $s,
    );
    
    $d->run;
    $d->destroy;
}

# Refers to right.
# +1 when dl is added, -1 when removed
sub update_scroll_area {
    shift if $_[0] eq __PACKAGE__;
    my $i = shift;
    $Scrollarea_height += ($HP + $RIGHT_SPACING_V) * $i;
    $Scrollarea_height = max $Scrollarea_height, 0;
    
    # first num just needs to be big
    $W_ly->right->set_size(2000, $Scrollarea_height);

    my $sb = $W_sw->right->get_vscrollbar or return;
    $sb->set_value($Scrollarea_height);
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
    $G->last_mid_inc;
    init_download($url, undef, $G->last_mid);
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

sub movie_panic_while_waiting {
    my ($mid, $errstr) = @_;
    movie_panic($mid, $errstr);

    remove_download_entry($mid);
}

sub movie_panic {
    # errstr can be undef
    my ($mid, $errstr) = @_;
    my $err = $errstr // '';
    err "Error getting movie" . ($err ? ": $err" : '.');

    # no warn -- object might already have been deleted.
    download_stopped($mid, 1);
}

sub profile_dialog {
    my ($profiles) = @_;
    
    # name => dir
    my %profiles = %$profiles;

    my $a = list_choice_dialog(\%profiles, "Choose profile:");
}

sub list_choice_dialog {
    my ($choices, $text, $opts) = @_;
    $opts //= {};
    my $allow_cancel = $opts->{allow_cancel} // 0;

    my $dialog = make_dialog();

    $dialog->set_size_request(300, -1);

    my (@keys, %lookup);
    if (ref $choices eq 'ARRAY') {
        @keys = @$choices;
        %lookup = map { $_ => $_ } @keys;
    }
    elsif (ref $choices eq 'HASH') {
        @keys = keys %$choices;
        %lookup = %$choices;
    }
    else { die }

    my ($box, $combo_box) = make_list_choice($choices, $text);

    my $ca = $dialog->get_content_area;
    my $aa = $dialog->get_action_area;

    my $fr = Gtk2::Frame->new;
    $fr->add($box);

    $ca->add($fr);

    my $response;

    my $al = Gtk2::Alignment->new(0,0,0,0);
    my $ok = Gtk2::Button->new_from_stock('gtk-ok');
    $al->add($ok);
    $aa->add($al);

    $ok->signal_connect('clicked', sub {
        my ($self, $blah) = @_;
        $response = $lookup{$combo_box->get_active_text} or warn;
        $dialog->destroy;
    });

    if ($allow_cancel) {
        my $al = Gtk2::Alignment->new(0,0,0,0);
        my $c = Gtk2::Button->new_from_stock('gtk-cancel');
        $al->add($c);
        $aa->add($al);

        $c->signal_connect('clicked', sub {
            my ($self, $blah) = @_;
            $response = undef;
            $dialog->destroy;
        });
    }

    $dialog->show_all;

    $dialog->run;

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
    $W_sb->main->pop(STATUS_OD);
}

sub set_output_dir {
    my ($od) = @_;
    $Output_dir = $od;
    main::set_output_dir($Output_dir);

    timeout(100, sub {
        $W_lb->od or return 1;
        $W_lb->od->set_label($T->output_dir . " $Output_dir", { size => 'small' });
        0;
    });
}

sub simulate {

return;

    my $SIM_TMP = main::make_tmp_dir();
    my $sim_idx = 0;
    set_pane_position($G->width / 2);
    timeout(1000, sub {
        $G->last_mid_inc;
        my $mid = $G->last_mid;
        my $size = int rand 1e6;
        my $of = "$SIM_TMP/blah$mid.flv";
        my $err_file = 'null';
        my $pid = -1234;
my $did = undef;
        queue_download($did, $mid, $of, $size);

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
            return file_progress({ simulate => 1}, $mid, $of, $size);
        });

        return ++$sim_idx == 10 ? 0 : 1;
    });
}

sub redraw {
    # And all children.
    $W->queue_draw;
}

sub left {
    my $w = shift;
    my $al = Gtk2::Alignment->new(0,0,0,0);
    $al->add($w);
    $al;
}

# ret 0: cancel, 1: go
sub replace_file_dialog {
    my $of = shift;

    my $dialog = Gtk2::MessageDialog->new ($W,
        'modal',
        'question', 
        'yes-no', 
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

    return 1;
}

# sets 4 globals
sub get_q_and_t_dialog {
    my $dialog = make_dialog();

    my $c = $dialog->get_content_area;
    my $a = $dialog->get_action_area;

    my $idx_ask_q = -1 + scalar list $G->qualities;
    my $idx_ask_t = -1 + scalar list $G->types;

    my ($boxq, $combo_boxq) = make_list_choice($G->qualities, $T->pq2);
    my ($boxt, $combo_boxt) = make_list_choice($G->types, $T->pt2);

    $combo_boxq->set_active($G->preferred_quality);
    $combo_boxt->set_active($G->preferred_type);

    # return
    my $is_tolerant_about_quality = $G->is_tolerant_about_quality;
    my $is_tolerant_about_type = $G->is_tolerant_about_type;
    my ($quality, $type);

    my $fb_cb_q = Gtk2::CheckButton->new('');

    $fb_cb_q->set_active($G->is_tolerant_about_quality);

    sig $fb_cb_q, 'toggled', sub {
        my $i = ! $G->is_tolerant_about_quality;
        $G->is_tolerant_about_quality($i);
        $is_tolerant_about_quality = $i;
    };

    my $fb_cb_t = Gtk2::CheckButton->new('');
    $fb_cb_t->set_active($is_tolerant_about_type);

    sig $fb_cb_t, 'toggled', sub {
        my $i = ! $G->is_tolerant_about_type;
        $G->is_tolerant_about_type($i);
        $is_tolerant_about_type = $i;
    };

    sig $combo_boxq, 'changed', sub {
        if ($combo_boxq->get_active == $idx_ask_q) {
            $fb_cb_q->set_active(1);
            $fb_cb_q->set_sensitive(0);
        }
        else {
            $fb_cb_q->set_sensitive(1);
        }
    };

    sig $combo_boxt, 'changed', sub {
        if ($combo_boxt->get_active == $idx_ask_t) {
            $fb_cb_t->set_active(1);
            $fb_cb_t->set_sensitive(0);
        }
        else {
            $fb_cb_t->set_sensitive(1);
        }
    };

    my $vb = Gtk2::VBox->new(0);
    $vb->add($boxq);
    ALLOW_SYNC and $vb->add($fb_cb_q);
    $vb->add($boxt);
    ALLOW_SYNC and $vb->add($fb_cb_t);

    my $l = $L->new($T->overwrite, { size => 'small' });
    $vb->add($l);

    $c->add($vb);

    cb_set_label($fb_cb_q, $T->fb, { size => 'small' } );
    cb_set_label($fb_cb_t, $T->fb, { size => 'small' } );

    my $ok = Gtk2::Button->new_from_stock('gtk-ok');
    my $cancel = Gtk2::Button->new_from_stock('gtk-cancel');

    sig $ok, 'clicked', sub {
        $quality = $combo_boxq->get_active;
        $type = $combo_boxt->get_active;
        $G->preferred_quality($quality);
        $G->preferred_type($type);
        $dialog->destroy;
    };

    sig $cancel, 'clicked', sub {
        $dialog->destroy;
    };

    $a->add($_) for $ok, $cancel;

    $dialog->show_all;
    $dialog->run;

    return ($quality, $is_tolerant_about_quality, $type,
        $is_tolerant_about_type);

}

sub make_list_choice {
    my ($choices, $text) = @_;

    my (@keys, %lookup);
    if (ref $choices eq 'ARRAY') {
        @keys = @$choices;
        %lookup = map { $_ => $_ } @keys;
    }
    elsif (ref $choices eq 'HASH') {
        @keys = keys %$choices;
        %lookup = %$choices;
    }
    else { die }

    my $id_col = 0;

    my $model = Gtk2::ListStore->new ('Glib::String');
    for (@keys) {
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

    my $vb = Gtk2::VBox->new(0);

    my $l = $L->new($text);
    $vb->pack_start($l, 1, 0, 2);
    $vb->pack_start($combo_box, 0, 0, 10);

    my $hb = Gtk2::HBox->new;
    $hb->pack_start($vb, 1, 0, 10);

    return ($hb, $combo_box);
}

sub cb_set_label {
    my ($cb, $text, $opt) = @_;
    
    my $l = ($cb->get_children)[0];
    $L->set_label($l, $text, $opt);
}

sub set_pref_labels {
    # desired / required 
    my $q = $G->is_tolerant_about_quality ? $T->pq2 : $T->pq3;
    my $t = $G->is_tolerant_about_type ? $T->pt2 : $T->pt3;
    my $prefq = $G->qualities->[$G->preferred_quality];
    my $preft = $G->types->[$G->preferred_type];
    $W_lb->pq->set_label("$q $prefq", { size => 'small' });
    $W_lb->pt->set_label("$t $preft", { size => 'small' });
}


sub get_image_button {
    shift if $_[0] eq __PACKAGE__;
    my ($which, $which_hover) = @_;

    my $im = Gtk2::Image->new;

    my $pix_normal = Gtk2::Gdk::Pixbuf->new_from_file($G->img($which));
    $im->set_from_pixbuf($pix_normal);

    my $eb = Gtk2::EventBox->new;
    $eb->modify_bg('normal', $Col->white);
    $eb->add($im);

    if ($which_hover) {
        my $pix_hover = Gtk2::Gdk::Pixbuf->new_from_file($G->img($which_hover));
        $eb->signal_connect('enter-notify-event', sub {
            $im->set_from_pixbuf($pix_hover);
        });

        $eb->signal_connect('leave-notify-event', sub {
            $im->set_from_pixbuf($pix_normal);
        });
    }

    return $eb;
}

sub get_geometry {
    my ($w) = @_;
    my $gdk_w = $w->get_window or warn, return;
    my ($x, $y, $width, $height, $depth) = $gdk_w->get_geometry;
    return {
        x => $x,
        y => $y,
        width => $width,
        w => $width,
        height => $height,
        h => $height,
        depth => $depth,
    };
}

1;



=head

pack_start(obj, expand, fill, padding)
    fill has no effect if expand is 0.

