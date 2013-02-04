package Fish::Youtube::Gtk;

# needs refactor -- too much crap in this module


use Fish::Youtube::DownloadThreads;

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

my $RIGHT_SPACING_V = 15;

# separation proportion
my $PROP = .5;

my $STATUS_PROP = .7;

my $SCROLL_TO_TOP_ON_ADD = 1;

my $T = o(
    output_dir => "Output dir:",
    pq  => "Preferred quality:",
    pt  => "Preferred type:",
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
    pq          => Gtk2::EventBox->new,
    pt          => Gtk2::EventBox->new,
    od          => Gtk2::EventBox->new,
    info        => Gtk2::EventBox->new,
    cancel_btn  => Gtk2::EventBox->new,
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

my $Tree_data_magic;

my $W;

my $Output_dir;

#globals

my $G = o(

    # inited then calculated
    height => $HEIGHT,
    # calculated
    width => -1,

    auto_start_watching => 1,

    init => 0,
    last_mid_in_statusbar => -1,

    # two ways to use hashes, bit different possibilities
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

    # auto add methods last_xxx_inc, last_xxx_dec.
    '+-last_mid' => -1,
    '+-last_idx' => -1,
    '+-last_did' => -1,

    # medium
    preferred_quality => 1,
    # mp4
    preferred_type => 0,

    qualities => [ Fish::Youtube::Get->qualities ],
    types => [ Fish::Youtube::Get->types ],

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

    $W_eb->$_->modify_bg('normal', $Col->white) for keys %$W_eb;

    my $button_add = Gtk2::EventBox->new;
    $button_add->add(Gtk2::Image->new_from_file($G->img('add')));
    $button_add->signal_connect('button-press-event', sub {
        my $response = inject_movie();
    });

    set_cursor_timeout($button_add, 'hand2');

    $l_buttons->pack_start($button_add, 0, 0, 10);

    $W_sw->left->set_policy('never', 'automatic');

    $W_sl->hist->set_headers_visible(0);

    $W_sw->left->add($W_sl->hist);
    $W_sw->left->show_all;

    # Tree_data_magic is tied
    $Tree_data_magic = $W_sl->hist->{data};

    $W_sl->hist->signal_connect (row_activated => sub { row_activated(@_) });

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

    for ('pq', 'pt') {
        my $eb = $W_eb->$_;
        $eb->add($W_lb->$_);
        set_cursor_timeout($eb, 'hand2');
        $eb->signal_connect('button-press-event', sub {
                #
        });
    }

    $W_lb->od->modify_bg('normal', $Col->black);

    # expand, fill, padding
    # fill has no effect if expand is 0.
    $outer_box->pack_start($W_hp->main, 1, 1, 0);

    $W_lb->od->set_label($T->output_dir, { size => 'small', color => 'red'});

    $W_lb->pq->set_label($T->pq . $G->qualities->[$G->preferred_quality], { size => 'small' });
    $W_lb->pt->set_label($T->pt . $G->types->[$G->preferred_type], { size => 'small' });

    # leftmost col, rightmost col, uppermost row, lower row, optx, opty, padx, pay
    my $oo = [qw/ expand shrink fill /];
    my $ooo = 'shrink';

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
        $t->attach($W_sb->main, 0, 1, 0, 1, $ooo, $ooo, 10, 10);
        $t->attach(left($auto_start_cb), 1, 2, 0, 1, $ooo, $ooo, 10, 10);
        $t->attach($W_eb->od, 2, 3, 1, 2, $ooo, $ooo, 10, 10);

        #$t->attach($W_eb->pq, 1, 2, 1, 2, $ooo, $ooo, 10, 10);
        #$t->attach($W_eb->pt, 2, 3, 1, 2, $ooo, $ooo, 10, 10);

        my $vb = Gtk2::VBox->new;
        {
            my $al = Gtk2::Alignment->new(0,0,0,0);
            $al->add($W_eb->pq);
            $vb->add($al);
        }
        {
            my $al = Gtk2::Alignment->new(0,0,0,0);
            $al->add($W_eb->pt);
            $vb->add($al);
        }
        $t->attach($vb, 1, 2, 1, 2, $ooo, $ooo, 10, 10);

        $outer_box->pack_end($t, 0, 0, 10);
    }

    $W_sb->main->set_size_request($G->width * .7, -1);

    $W_lb->od->set_size_request($G->width * .3, -1);

    $W_sb->main->set_has_resize_grip(0);


    if (0) {
        my $b = Gtk2::Button->new('a');
        $b->signal_connect('clicked', sub {
                # some debug
        });

        $outer_box->add($b);
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
        if (! $m or ! %$m) {
            @$Tree_data_magic = "No movies -- first browse somewhere in Firefox.";
            return 1;
        }
        else {
            unshift_r $G->movies_buf, $m;
        }
    }

    if ($first) {
        @$Tree_data_magic = ();
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

        $G->last_mid_inc;
        unshift @$Tree_data_magic, $t;
        unshift_r $G->movie_data, { mid => $G->last_mid, url => $u, title => $t};

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

        set_cursor($W, 'clock');
    start_download($u, $t, $mid);
}

sub start_download {
    my ($u, $t, $mid) = @_;

    # already downloaded /-ing
    return if $D->exists($mid);
    
    $G->last_did_inc;
    my $did = $G->last_did;

    if (! $Output_dir) {
        # remove_all doesn't seem to work.
        $W_sb->main->pop(STATUS_OD);
        $W_sb->main->push(STATUS_OD, 'Choose output dir first.');
        return;
    }

    $G->download_successful->{$mid} = 0;
    $G->auto_launched->{$mid} = 0;

    my $box;

    #my $tmp = main::make_tmp_dir();

    my $wait_s = "Trying to get '";
    $wait_s .= $t ? $t : 'manual download';
    $wait_s .= "' ";
    $G->is_waiting->{$mid} = $wait_s;

    $G->last_mid_in_statusbar($mid);
    $W_sb->main->push($mid, $wait_s);

    state $first = 1;

    my $manual;
    my $of;

my $prefq = '';
my $preft = '';
my $itaq = -1;
my $itat = -1;

    my $async = 1;
    $async = 0 unless $prefq && $preft;

    # manual download -- get name from youtube-get
    if (! $t) {
        $manual = 1;
    } 
    
    else {
        # if any prompting, we can't know outfile. 
        # otherwise, set it here, to allow async

        if ($async) {
            $of = "$Output_dir/$t.EXT";

            main::sanitize_filename(\$of);

            if (-r $of) {
                return unless replace_file_dialog($of);
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
    #my ($pid, $err_file) = main::start_download($mid, $u, ($manual ? undef : $of), $tmp, $Output_dir, $force_get);
    # we are still in an event callback
    # positive means no err so far and thread was launched.
    # undef means err
    # -1 means cancelled.
    my $tid;

    if ($async) {
        $tid = main::start_download_async($did, $mid, $u, $of, $prefq, $preft, $itaq, $itat);
    }
    else {
        $tid = main::start_download_sync($did, $mid, $u, $Output_dir, $prefq, $preft, $itaq, $itat) ;
    }

    my $status = $Fish::Youtube::DownloadThreads::Status_by_did{$did};

    if (! $tid) {
        # subproc failed.

        my $e;
        if ($status->{status} eq 'error') {
            war "Download thread reported error.";
            warn $e if $e = $status->{errstr};
        }

        movie_panic_while_waiting($mid, $e);

        return;
    }
    # not sure if this happens.
    elsif ($tid == -1) {
        #cancelled 
        D 'cancelled.';
        return;
    }

    D 'tid', $tid;

    # Thread launched and signalled 'ready'. 

    my $md = $Fish::Youtube::DownloadThreads::Metadata_by_tid{$tid};

    if ($status->{status} eq 'error') {
        war "Download thread reported error.";
        my $e;
        warn $e if $e = $status->{errstr};
    }

    my $size = $md->{size} or warn, return;
    $md->{of} or warn, return;

    timeout 500, sub {
        #D 'checking for tid', $tid;

        if ($status->{status} eq 'error') {
            war "Download thread reported error.";
            my $e;
            warn $e if $e = $status->{errstr};
            movie_panic_while_waiting($mid, $e);
            return 0;
        }

        # name is only needed if we didn't specify $of
        $of //= $md->{of};

        D 'got md', 'name', $of, 'size', $size;

        # got it, add download and kill timeout

        if ($manual) {
            $t = basename $of;
            $t =~ s/\.\w+$//;
        }

        add_download($mid, $t, $size);

        my $cur_size = -1;

        timeout( 200, sub { 
            return file_progress({ simulate => 0}, $mid, $of, \$cur_size, $size);
        });
        
        #timeout 500, sub { auto_start_watching($mid, \$cur_size, $size, $o) };
        

        return 0;
    }
    # / child wait
}

sub auto_start_watching {
    my ($mid, $cur_size_r, $size, $file) = @_;

    $G->auto_launched->{$mid} and return 0;

    if ($G->auto_start_watching) {
        if ($$cur_size_r / $size * 100 > $AUTO_WATCH_PERC) {
            $G->auto_launched->{$mid} = 1;
            main::watch_movie($file);
        }
    }
    return 1;
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
    my ($mid, $file, $cur_size_r, $size) = @_;
    my $s = stat $file or warn(), return 1;

    my $d = $D->get($mid);

    # download object destroyed for some reason
    if (! $d and ! $simulate) {
        movie_panic($mid);
        return 0;
    }

    $$cur_size_r = $s->size;
    $d->prog($$cur_size_r);

    # process not running -- finished or aborted

    # ps, heavy?

#    if ( ! sys_ok "ps $pid" and ! $simulate ) {
    #
    #    D2 'cur_size', $$cur_size_r;
    #
    #    # finished
    #    if ($$cur_size_r == $size) {
    #        download_finished($mid);
    #        return 0;
    #    }
    #
    #    # cancelled / other problem
    #    else {
    #        movie_panic($mid);
    #        return 0;
    #    }
    #}

    # still downloading
    return 1;
}

sub add_download {

    my ($mid, $title, $size, $of) = @_;

    # downloads added faster than poll_downloads can grab them (shouldn't
    # happen)
    warn "download buf not empty" if $G->download_buf;

    $G->last_idx_inc;
    $G->download_buf({
        idx => $G->last_idx,
        mid => $mid,
        size => $size,
        title => $title,
        of => $of,
    });
}

sub poll_downloads {

    my %db = $G->download_buf or return 1;

    # start new download

    my $size = $db{size};
    my $title = $db{title};
    my $idx = $db{idx};
    my $of = $db{of};

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
        #of      => $of,
        pixmap  => $pixmap,
    );

    $G->download_buf({});

    my $anarchy = Fish::Youtube::Anarchy->new(
        width => $WP,
        height => $HP,
    );

    my $hb = Gtk2::HBox->new;
    my $vb = Gtk2::VBox->new;

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

    {
        my $eb_im = $W_eb->cancel_btn;
        $eb_im->add($im);

        $eb_im->signal_connect('enter-notify-event', sub {
            $im->set_from_pixbuf($pix_hover);
        });

        $eb_im->signal_connect('leave-notify-event', sub {
            $im->set_from_pixbuf($pix_normal);
        });

        $eb_im->signal_connect('button-press-event', sub {
            cancel_download($mid);
            # 1 means don't propagate (we are inside $eb)
            return 1;
        });

        $vb->add($l1);
        $hb->add($l2);
        $hb->add($l3);
        $hb->add($l4);

        my $hb_al = Gtk2::Alignment->new(0,0,0,0);
        $hb_al->add($hb);
        $vb->add($hb_al);
        $hb->pack_start($eb_im, 0, 0, 20);
    }

    $_->modify_bg('normal', $Col->white) for $vb, $hb;

    {
        my $eb = $W_eb->info;
        $G->info_box->{$mid} = $eb;
        $eb->add($vb);
        $eb->signal_connect('button-press-event', sub {
            main::watch_movie($of);
        });

        $W_ly->right->put($eb, $INFO_X, $RIGHT_PADDING_TOP + $idx * ($HP + $RIGHT_SPACING_V));
    }

    remove_wait_label($mid);


    update_scroll_area(+1);
    $W_ly->right->show_all;

    set_cursor_timeout($G->info_box->{$mid}, 'hand2');

    $G->cancel_images->{$mid} = $im;

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

# should hook into tid
    my $idx = $d->idx;

    # will cancel timeouts
    $d->delete;

    $G->last_idx_dec;
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
    $G->last_mid_inc;
    #start_download($url, 'manual ' . ++$i, $Last_mid);
    start_download($url, undef, $G->last_mid);
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
    my ($mid, $errstr) = @_;
    movie_panic($mid, $errstr);
    remove_wait_label($mid);
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

    my $dialog = make_dialog();

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

    $dialog->set_size_request(300, -1);
    my $ca = $dialog->get_content_area;

    my $fr = Gtk2::Frame->new;

    my $hb = Gtk2::HBox->new;
    my $vb = Gtk2::VBox->new(0);

    $fr->add($hb);
    $ca->add($fr);
    $hb->pack_start($vb, 1, 0, 10);

    my $l = $L->new($text);
    $vb->pack_start($l, 1, 0, 10);
    $vb->pack_start($combo_box, 0, 0, 10);

    my $response;

    my $aa = $dialog->get_action_area;
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
        $W_lb->od->set_label($T->output_dir . " $Output_dir", { size => 'small' });
        0;
    });
}

sub set_cursor_timeout {
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

sub simulate {
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
        add_download($mid, $of, $size);

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
            Gtk2::Gdk::Threads->enter;

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

            Gtk2::Gdk::Threads->leave;
    if ($response ne 'yes') {
        return;
    }

    if (! sys_ok qq, rm -f "$of", ) {
        mess "Couldn't remove file", Y $of;
        return;
    }

    return 1;
}

1;
