package Fish::Youtube::Components::MoviesList;

use 5.10.0;

use Moose;
use Fish::Youtube::Utility;

has _buf => (
    is => 'rw',
    isa => '',
);

has container => (
    is  => 'ro',
    isa => '%',
);

has profile_dir => (
    is  => 'rw',
    isa => 'Maybe',
);

# tree
has widget => (
    is => 'ro',
    isa => 'Gtk2::Widget',
    writer => '_set_widget',
);

# same as widget
has _tree => (
    is => 'rw',
    isa => 'Gtk2::SimpleList',
);

has cb_row_activated => (
    is  => 'ro',
    isa => 'CodeRef',
);

has _tree_data_magic => (
    is => 'rw',
    isa => 'ArrayRef',
);

has _buf => (
    is  => 'rw',
    isa => 'ArrayRef',
    default => sub {[]},
);

has _data => (
    is  => 'rw',
    isa => 'ArrayRef',
    default => sub {[]},
);

my $G = 'Fish::Youtube::Gtk';
my $SCROLL_TO_BOTTOM_ON_ADD = 1;


sub BUILD {
    my ($self) = @_;

    # is a Treeview
    my $tree = Gtk2::SimpleList->new(
        # text w/pango
        '' => 'markup',
    );
    $tree->set_headers_visible(0);
    $self->_set_widget($tree);
    $self->_tree($tree);

    # Tree_data_magic is tied
    my $tree_data_magic = $tree->{data};

    $self->_tree_data_magic($tree_data_magic);

    $tree->signal_connect (
        row_activated => sub { 
            if (my $c = $self->cb_row_activated) {
                $c->(@_);
            }
        });

    timeout 1000, sub {
        $self->poll_movies;
        $self->update_movie_tree;
        return 1;
    }

}

sub poll_movies {
    my ($self) = @_;

    my $p = $self->profile_dir;
    if (! $p) {
        if (my $q = main->profile_dir) {
            $self->profile_dir($q);
            $p = $q;
        }
        else {
            return 1;
        }
    }

    my $hist = Fish::Youtube::History->new(
        num_movies => 15,
        profile_dir => $p,
    );

    $hist->update;
    my $m = $hist->movies;

    # no undefined element
    if (@$m and not grep { not defined } @$m) {
        $self->set_buf($m);
    }

    return 1;
}

sub update_movie_tree {
    my ($self) = @_;

    state $last;
    state $first = 1;

    my $i = 0;

    my $buf = $self->_buf;
    my $data_magic = $self->_tree_data_magic;

    #$G->movies_buf or return 1;

    # single value of {} means History returned exactly 0 entries
    {
        my $m = shift_r $buf;
        if (! $m or ! %$m) {
            @$data_magic = "No movies -- first browse somewhere in Firefox.";

            return 1;
        }
        else {
            unshift_r $buf, $m;
        }
    }

    if ($first) {
        @$data_magic = ();
        $first = 0;
    }

    #@Movies_buf: latest in front

    my @m = list $buf;
    $self->_buf([]);

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

    my $tree = $self->_tree;
    my $num_in_tree_before_add = $self->num_children_in_tree;

    for (reverse @n) {
        my ($u, $t) = ($_->{url}, $_->{title});

        $t =~ s/ \s* - \s* youtube \s* $//xi;

        my $mid = $G->get_mid;

        push @$data_magic, qq, <span size="small">$t</span> ,;
        push_r $self->_data, { mid => $mid, url => $u, title => $t};

        # first in buffer is last
        $last = $u if ++$i == @n;
    }

    if (@n and $SCROLL_TO_BOTTOM_ON_ADD) {
        timeout 50, sub {
            my $num_ch = $self->num_children_in_tree;
            if ($num_ch != $num_in_tree_before_add) {
                # Does minimum necessary to scroll that row into view.
                $tree->scroll_to_cell(
                    Gtk2::TreePath->new_from_indices($num_ch - 1),
                    # col
                    undef,
                );
            }

            return 0;
        };
    }

    1;
}


sub set_buf {
    my ($self, $_movies_buf) = @_;

    #@Movies_buf: latest in front
    unshift_r $self->_buf, $_ for reverse @$_movies_buf;
}

sub get_data {
    my ($self, $idx) = @_;
    $self->_data->[$idx] or warn, return;
}

sub num_children_in_tree {
    my ($self) = @_;
    my $treeview = $self->_tree;
    return $treeview->get_model->iter_n_children;
}

1;
