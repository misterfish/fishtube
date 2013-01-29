package Fish::Youtube::Download;

my $c = 'Fish::Youtube::Download';

use 5.10.0;

use Moose;

use Fish::Youtube::Utility;

# This class generates Download objects, and also stores them in a global
# variable, using id prop of object.

my %downloads;
my $num_drawing = 0;
my $num_downloading = 0;

# for now, equal to $mid in Gui. works because a movie has max one download
# object.

has id => (
    is  => 'ro',
    isa => 'Num',
    required => 1,
);

# for drawing pixmaps
has idx => (
    is  => 'ro',
    isa => 'Int',
    required => 1,
    traits => ['Counter'],
    handles => {
        idx_inc => 'inc',
        idx_dec => 'dec',
    },
);

has size => (
    is  => 'ro',
    isa => 'Int',
    required => 1,
);

has title => (
    is  => 'ro',
    isa => 'Str',
    required => 1,
);

has of => (
    is  => 'ro',
    isa => 'Str',
    required => 1,
);

has pid => (
    is  => 'ro',
    isa => 'Int',
    required => 1,
);

has pixmap => (
    is  => 'rw',
    isa => 'Gtk2::Gdk::Pixmap',
);

has is_drawing => (
    is  => 'rw',
    isa => 'Bool',
);

has is_downloading  => (
    is  => 'rw',
    isa => 'Bool',
);

has prog => (
    is  => 'rw',
    isa => 'Num',
    default => -1,
);

sub BUILD {
    my ($self, @args) = @_;
    $self->started_drawing;
    $self->started_downloading;
    $downloads{$self->id} = $self;
}

sub started_drawing {
    my ($self) = @_;
    if (! $self->is_drawing) {
        $self->is_drawing(1);
        $num_drawing++;
    }
}

sub stopped_drawing {
    my ($self) = @_;
    if ($self->is_drawing) {
        $self->is_drawing(0);
        $num_drawing--;
    }
}

sub started_downloading {
    my ($self) = @_;
    if (! $self->is_downloading) {
        $self->is_downloading(1);
        $num_downloading++;
    }
}

sub stopped_downloading {
    my ($self) = @_;
    if ($self->is_downloading) {
        $self->is_downloading(0);
        $num_downloading--;
    }
}

sub delete {
    my ($self) = @_;
    $c->c_delete($self->id);
}

# class

sub c_started_downloading {
    my ($class, $id) = @_;
    my $d = $class->get($id) or warn;
    $d->started_downloading;
}

sub c_stopped_downloading {
    my ($class, $id, $nowarn) = @_;
    if (my $d = $class->get($id)) {
        $d->stopped_downloading;
    }
    else {
        $nowarn or warn;
    }
}

sub c_started_drawing {
    my ($class, $id) = @_;
    my $d = $class->get($id) or warn;
    $d->started_drawing;
}

sub c_stopped_drawing {
    my ($class, $id) = @_;
    my $d = $class->get($id) or warn;
    $d->stopped_drawing;
}

sub c_delete {
    my ($class, $id) = @_;

    $class->c_stopped_downloading($id);
    $class->c_stopped_drawing($id);

    delete $downloads{$id} or warn;
}

sub exists {
    my ($class, $id) = @_;
    return $downloads{$id} ? 1 : 0;
}

sub make_pixmaps {
    my ($class) = @_;

    for my $id (keys %downloads) {
        my $d = $downloads{$id};
        next unless $d->is_drawing;
        $d->pixmap(Fish::Youtube::Gtk->make_pixmap);
    }
}

sub all {
    my ($class) = @_;
    # nice to sort on id, not necessary
    return map { $downloads{$_} } sort { $a <=> $b} keys %downloads;
}

sub get {
    my ($class, $id) = @_;
    return $downloads{$id};
}

sub is_anything_drawing {
    my ($class) = @_;
    return $num_drawing ? 1 : 0;
}

1;

