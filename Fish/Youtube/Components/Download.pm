package Fish::Youtube::Components::Download;

use 5.10.0;

use Moose;
use Fish::Youtube::Utility;

has _pixmap => (
    is  => 'rw',
    isa => 'Gtk2::Gdk::Pixmap',
);

has _eb_controls => (
    is  => 'rw',
    isa => 'Gtk2::EventBox',
);

has _anarchy => (
    is  => 'rw',
    isa => 'Fish::Youtube::Components::Anarchy',
);

has container => (
    is => 'ro',
    isa => 'Gtk2::EventBox',
    writer => '_set_container',
);

# unique enough? XX
has mid => (
    is  => 'ro',
    isa => 'Int',
);

has _label_cur_size => (
    is  => 'rw',
    isa => 'Gtk2::Label',
);

has _label_slash => (
    is  => 'rw',
    isa => 'Gtk2::Label',
);

has file_size => (
    is  => 'rw',
    isa => 'Int',
);

has title => (
    is  => 'ro',
    isa => 'Str',
);

my $HP = 50;
my $WP = 50;

my $G = 'Fish::Youtube::Gtk';
my $L = 'Fish::Gtk2::Label';

sub height { $HP }
sub width { $WP }

sub BUILD {

    my ($self, $file_size) = @_;

    $self->remake_pixmap;

    my $anarchy = Fish::Youtube::Components::Anarchy->new(
        width => $WP,
        height => $HP,
    );
    $self->_anarchy($anarchy);

    my $Col = $G->col;

    my $vb = Gtk2::VBox->new;
    $vb->modify_bg('normal', $Col->white);

    my $c1 = $Col->black;
    my $c2 = $G->get_color(100,100,33,255);
    my $c3 = $c2;
    my $c4 = $c1;

    # title
    my $l1 = $L->new($self->title, { size => 'small' });
    $l1->modify_fg('normal', $c1);

    # cur_size
    my $l2 = $L->new;
    $l2->modify_fg('normal', $c2);
    $self->_label_cur_size($l2);

    # /
    my $l3 = $L->new('/', { size => 'small' });
    $l3->modify_fg('normal', $c3);
    $self->_label_slash($l3);

    # total
    my $l4 = $L->new(nice_bytes_join $self->file_size, { size => 'small' });
    $l4->modify_fg('normal', $c4);

    my $eb_im_cancel = $G->get_image_button('cancel', 'cancel_hover'); 
    my $eb_im_delete = $G->get_image_button('delete', 'delete_hover'); 
    my $eb_im_blank = $G->get_image_button('blank');

    my $mid = $self->mid;

    $eb_im_cancel->signal_connect('button-press-event', sub {
        $G->cancel_download($mid);
        $G->remove_download_entry($mid);
        # 1 means don't propagate (we are inside $eb)
        return 1;
    });

    $eb_im_delete->signal_connect('button-press-event', sub {
        $G->cancel_download($mid);
        $G->remove_download_entry($mid);

        # and delete XX

        # 1 means don't propagate (we are inside $eb)
        return 1;
    });

    # title
    $vb->add($l1);

    {
        my $hb = Gtk2::HBox->new;

        # cur 
        $hb->pack_start($l2, 0, 0, 0);
        # / 
        $hb->pack_start($l3, 0, 0, 0);
        # total
        $hb->pack_start($l4, 0, 0, 0);

        $hb->pack_end($eb_im_delete, 0, 0, 0);
        $hb->pack_end($eb_im_cancel, 0, 0, 5);

        # bottom, doesn't work
        #my $al = Gtk2::Alignment->new(0, 1, 0, 0);

        my $eb = Gtk2::EventBox->new;
        $eb->add($hb);

        my $hb_outer = Gtk2::HBox->new;
        $hb_outer->pack_start($eb_im_blank, 0, 0, 0);
        $hb_outer->pack_start($eb, 1, 1, 0);

        $vb->add($hb_outer);

        $eb->modify_bg('normal', $Col->white);

        $self->_eb_controls($eb);
    }

    {
        # Main container.
        my $eb = Gtk2::EventBox->new;
        $eb->modify_bg('normal', $Col->white);

        $self->_set_container($eb);

        $eb->add($vb);
        $eb->signal_connect('button-press-event', sub {
            $self->cb_watch_movie->();
        });

        $eb->show_all;
    }

    #remove_wait_label($mid);

    $G->update_scroll_area(+1);

    set_cursor_timeout $self->container, 'hand2';
}

# Called by Download::make_pixmaps
sub remake_pixmap {
    my ($self) = @_;
    my $pixmap = $G->make_pixmap($WP, $HP);
    $G->clear_pixmap($pixmap);

    $self->_pixmap($pixmap);
}

# needed by expose_drawable
sub pixmap { shift->_pixmap }

sub update {
    my ($self, $cur_size) = @_;

    # get every time.
    my $pixmap = $self->_pixmap;

    # shouldn't happen
    if (not $pixmap) {
        warn "pixmap not defined";
        return 0;
    }

    my $l = $self->_label_cur_size or warn, return;
    my $file_size = $self->file_size or warn, return;

D 'setting!', 'cur_size', $cur_size;

    $l->set_label(nice_bytes_join $cur_size, { size => 'small' });

    my $perc = $cur_size / $file_size * 100;

    state $last = -1;

    my $anarchy = $self->_anarchy;

    if ($last != $cur_size) {
        my $s = sprintf "%d / %d (%d%%)", $cur_size, $file_size, $perc;

        # animate here
        my $surface = $anarchy->draw($perc / 100);

        $G->draw_surface_on_pixmap($pixmap, $surface);
    }

    $last = $cur_size;

    if ($perc >= 100) {
        my $surface = $anarchy->draw(1, { last => 1});

        D2 'animation loop: completed, stopping';

        $G->draw_surface_on_pixmap($pixmap, $surface);

        $self->finished;

        return 0;
    }

    return 1;
}

sub finished {
    my ($self) = @_;

    # Hide controls but show with mouseover.
    
    my $i = $self->container;
    my $c = $self->_eb_controls;
    $c->hide;

    sig $i, 'enter-notify-event', sub {

        my ($self, $event) = @_;

        # only interested if entered from outside (not from inner boxes)
        return if $event->detail eq 'inferior';

        $c->show;
    };

    sig $i, 'leave-notify-event', sub {
        my ($self, $event) = @_;

        # only interested if leaving towards outside (not towards inner
        # boxes)
        my $detail = $event->detail;
        return if $detail eq 'inferior';

        $c->hide;
    };
}

    #$_->hide for $G->controls->{$mid}, list $G->size_label->{$mid};


1;
