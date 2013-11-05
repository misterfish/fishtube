package Fish::Youtube::Components::MoviesList;

use 5.10.0;

use Moose;
use Fish::Youtube::Utility;
use Fish::Youtube::Utility 'd'; 
use Fish::Youtube::Utility::Gtk;

#my $POLL_TIMEOUT = 1000;
my $POLL_TIMEOUT = 500;

has _buf => (
    is => 'rw',
    isa => '',
);

has container => (
    is  => 'ro',
    isa => '%',
);

# set_profile_dir
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

has _history => (
    is => 'rw',
    isa => 'Fish::Youtube::History',
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

# ff bug
has _dont_update_tree => (
    is  => 'rw',
    isa => 'Bool',
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

    my $h = Fish::Youtube::History->new(
        #num_movies => 15,
        num_movies => 3,
        # can be undef
        profile_dir => $self->profile_dir,
    );

    $self->_history($h);

    timeout $POLL_TIMEOUT, sub {
        $self->poll_movies;
        $self->update_movie_tree;
        return 1;
    }
}

sub poll_movies {
    my ($self) = @_;

    my $hist = $self->_history;

    if (my $u = $hist->update) {
        if ($u == -1) {
            # special for ff bug
            $self->_dont_update_tree(1);
            return 1;
        }
        else {
            $self->_dont_update_tree(0);
        }
        my $m = $hist->movies;
        my @copy = list $hist->movies;

        ## no undefined element
        #if (@copy and not grep { not defined } @copy) {
        #$self->set_buf(\@copy);
        #}
        $self->set_buf(\@copy) if @copy;
    }
    # couldn't update
    else {
        $self->_dont_update_tree(1);
    }

    return 1;
}

sub update_movie_tree {
    my ($self) = @_;

    state $last;
    state $first = 1;

    # ff bug
    return 1 if $self->_dont_update_tree;

    my $i = 0;

    my $buf = $self->_buf;
    my $data_magic = $self->_tree_data_magic;

    #$G->movies_buf or return 1;

    # single value of {} means History returned exactly 0 entries
    {
        my $m = shiftr $buf;
        if (! $m or ! %$m) {
            @$data_magic = "No movies -- first browse somewhere in Firefox.";

            return 1;
        }
        else {
            unshiftr $buf, $m;
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
            D2 'pushing movie', d $_;
            push @n, $_;
        }
    }
    else {
        D2 'pushing movies', map { d $_ } @m;
        @n = @m;
    }

    my $tree = $self->_tree;
    my $num_in_tree_before_add = $self->num_children_in_tree;

    for (reverse @n) {
        my ($u, $t) = ($_->{url}, $_->{title});

        $t =~ s/ \s* - \s* youtube \s* $//xi;

        D2 'adding title to movieslist', $t;
        sanitize_pango(\$t);

        my $mid = $G->get_mid;

        push @$data_magic, qq, <span size="small">$t</span> ,;
        pushr $self->_data, { mid => $mid, url => $u, title => $t};

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
    unshiftr $self->_buf, $_ for reverse @$_movies_buf;
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

sub set_profile_dir {
    my ($self, $dir) = @_;
    $self->profile_dir($dir);
    $self->_history->profile_dir($dir);
}

1;
