#!/usr/bin/perl

package Fish::Youtube::History;

use 5.10.0;

use Moose;

use Fish::Youtube::Utility;
use Fish::Youtube::Utility 'error';
use Fish::Youtube::Iter;
use Fish::Class 'o';

use DBI;

has luakit => (
    is  => 'ro',
    isa => 'Bool',
);

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

has _sql => (
    is  => 'rw',
    # XX
    isa => 'Fish::Class',
);

around BUILDARGS => sub {
    my ($orig, $class, @args) = @_;
    my %construct = @args;

    return $class->$orig(%construct);
};

my $g = o(
    sql_firefox => o(
        col_last_visit_date => 'last_visit_date',
        cols => ['url', 'last_visit_date', 'title'],
        table_name => 'moz_places',
        col_uri => 'url',
        file => 'places.sqlite',
    ),
    sql_luakit => o(
        col_last_visit_date => 'last_visit',
        cols => ['uri', 'last_visit', 'title'],
        table_name => 'history',
        col_uri => 'uri',
        file => 'history.db',
    ),
);

sub BUILD {
    my ($self, @args) = @_;
    $self->_sql( $self->luakit ? 
        $g->sql_luakit :
        $g->sql_firefox
    );
    $self->connect;
}

sub connect {
    my ($self) = @_;
    my $pd = $self->profile_dir or
        return; # ok, it hasn't been set yet.

    my $filename = $self->_sql->file;
    my $file = "$pd/$filename";
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

    $self->_dbh or war("(Re)connecting"), $self->connect;

#    # Reconnect on every update. Necessary?
#    $self->connect or 
#        war("couldn't (re)connect"),
#        return; # ok, we don't know profile dir yet probably.

    my $num = $self->num_movies;

    my $lvd = $self->_sql->col_last_visit_date;
    my $cols = join ',', list $self->_sql->cols;
    my $table_name = $self->_sql->table_name;
    my $col_uri = $self->_sql->col_uri;

    my $wt = '';
    if (my $t = $self->_last_update_time) {
        # firefox format
        $t .= '000000' unless $self->luakit;

        $wt = " and $lvd > $t ";
    }

    my $sql = qq| 

    select $cols
        from $table_name
        where ($col_uri like '%youtube.com/watch%' or $col_uri like '%youtu.be/watch%') 
            $wt 
        order by $lvd desc limit $num | ;

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
            if ( ! $self->luakit and
                my $last = $self->_last_movie) {
                my $lt = $last->{title};
                $lt =~ s/ ^ $tri \s* //x;

                if ($title eq $lt) {
                    info 'Detected duplicate firefox thing, waiting';
                    return -1;
                }
else {
info 'unequal', $title, $lt unless $self->luakit;
}
            }

            $self->_last_update_time(time);
        }

        my ($domain, $rest) = ($url =~ m| http s? :// ([^/] +) (/ .+)? |x);

        $rest or warn, next;

        # Don't do nexts here -- could confusingly end up with few or no
        # results. Do as much as possible in the sql statement.

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
