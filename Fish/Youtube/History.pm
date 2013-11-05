#!/usr/bin/perl

package Fish::Youtube::History;

use 5.10.0;

use Moose;

use Fish::Youtube::Utility;
use Fish::Youtube::Utility 'error';
use Fish::Youtube::Iter;

#%
use DBI;

has movies => (
    is => 'ro',
    isa => 'ArrayRef',
    writer => 'set_movies',
    default => sub {[]},
);

has num_movies => (
    is => 'rw',
    isa => 'Num',
    default => 20,
);

has profile_dir => (
    is => 'rw',
    isa => 'Maybe',
);

has _dbh => (
    is => 'rw',
);

has _last_update_time => (
    is => 'rw',
    isa => 'Num',
);

has _last_movie => (
    is => 'rw',
    isa => 'HashRef',
);

around BUILDARGS => sub {
    my ($orig, $class, @args) = @_;
    my %construct = @args;

    # allow undef in constructor
    #defined $construct{profile_dir} or delete $construct{profile_dir};

    return $class->$orig(%construct);
};


sub BUILD {
    my ($self, @args) = @_;
}

sub connect {
    my ($self) = @_;
    my $pd = $self->profile_dir or
        return; # ok, it hasn't been set yet.

    my $file = "$pd/places.sqlite";
    my $dbh = DBI->connect(
        "dbi:SQLite:dbname=$file", "", "",
        {  
            # Perl strings retrieved from DB will contain chars.
            sqlite_unicode => 1,
            #### enable transactions, don't need begin_work
            ###AutoCommit => 0,
            AutoCommit => 1,
            PrintError => 1,
            RaiseError => 1,
        }
    );
    $self->_dbh($dbh);
}

# don't think we need this
sub disconnect {
    shift->_dbh->disconnect;
}

sub update {

    my ($self) = @_;

    # Reconnect on every update. Necessary?
    $self->connect or 
        return; # ok, we don't know profile dir yet probably.

    my $num = $self->num_movies;

    my $wt = '';
    if (my $t = $self->_last_update_time) {
        # firefox format
        $t .= '000000';
        $wt = " and last_visit_date > $t ";
    }

    my $sql = qq| 

    select url, last_visit_date, title
        from moz_places 
        where (url like '%youtube.com/watch%' or url like '%youtu.be/watch%') 
            $wt 
        order by moz_places.last_visit_date desc limit $num | ;

    my $r = $self->_dbh->selectall_arrayref($sql);

    my @new;

    # U+25B6 ▶ 
    my $tri = chr 0x25b6;

    while (my $iter = iterr $r) {
        my $i = $iter->k;
        my $data = $iter->v;

        my ($url, $date, $title) = @$data;
        $title or next;

        $title =~ s/ ^ $tri \s* //x;
        if ($i == 0) {
            if (my $last = $self->_last_movie) {
                my $lt = $last->{title};
                $lt =~ s/ ^ $tri \s* //x;

                if ($title eq $lt) {
                    info 'Detected duplicate firefox thing, waiting';
                    return -1;
                }
            }

            $self->_last_update_time(time);
        }

        my ($domain, $rest) = ($url =~ m| http s? :// ([^/] +) (/ .+)? |x);

        $rest or warn, next;

        # Bad to have nexts here, because could end up with empty list and
        # that's confusing.
        if (0) {
            my @s = split /\./, $domain;
            next if @s == 3 and $s[0] ne 'www';
        }

        #next if $domain and $domain ne 'www.youtube.com';
        #next if $rest =~ m|^/results|;
        #next if $rest =~ m|^/user|;
        D2 'history', 'url', $url, 'date', $date, 'title', $title;
        push @new, new_movie($url, $date, $title);
    }

    # ff bug/strangeness
    $self->_last_movie($new[0]) if @new;

    # ->movies only contains movies added since the last timestamp.
    $self->set_movies(\@new) if @new;

    1;
}

sub new_movie {
    my ($url, $date, $title) = @_;
    $url and $date and $title or die;
    return { url => $url, date => $date, title => $title };
}

1;
