#!/usr/bin/perl

package Fish::Youtube::History;

use 5.10.0;

use Moose;

sub error;
sub war;

use Fish::Youtube::Utility;

#%
use DBI;

has movies => (
    is => 'ro',
    isa => 'ArrayRef',
    writer => 'set_movies',
);

has num_movies => (
    is => 'rw',
    isa => 'Num',
    default => 20,
);

has profile_dir => (
    is => 'ro',
    isa => 'Str',
    writer => 'set_profile_dir',
);

has _dbh => (
    is => 'rw',
);

has _last_update_time => (
    is => 'rw',
    isa => 'Num',
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
    my $pd = $self->profile_dir;
    my $file = "$pd/places.sqlite";
    my $dbh = DBI->connect(
        "dbi:SQLite:dbname=$file", "", "",
        {  
            # Perl strings retrieved from DB will contain chars.
            sqlite_unicode => 1,
            # enable transactions, don't need begin_work
            AutoCommit => 0,
            PrintError => 1,
            RaiseError => 1,
        }
    );
    $self->_dbh($dbh);
}

sub update {

    my ($self) = @_;

    # need to reconnect to see updates apparently.
    $self->connect;

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

    # expires?
    my $r = $self->_dbh->selectall_arrayref($sql);

    my @d;
    if (@$r) {
        my $t = time;
        $self->_last_update_time($t);
    }
    else {
        # single {} means no movies
        @d = ({});
    }

    for (@$r) {
        my ($url, $date, $title) = @$_;
        $title or next;
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
#D2 'history', 'url', $url, 'date', $date, 'title', $title;
        push @d, new_movie($url, $date, $title);
    }

    $self->set_movies(\@d);
}

sub new_movie {
    my ($url, $date, $title) = @_;
    $url and $date and $title or die;
    return { url => $url, date => $date, title => $title };
}

sub error {
    my @s = @_;
    die join ' ', @s, "\n";
}

sub war {
    my @s = @_;
    warn join ' ', @s, "\n";
}

1;
