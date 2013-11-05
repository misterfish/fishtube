package Fish::Youtube::Anon;

use 5.10.0;
BEGIN {
    use Exporter();
    push @ISA, 'Exporter';
    @EXPORT_OK = 'o';
}

use strict;
use warnings;

our $AUTOLOAD;
sub new {
    shift;
    my %args = @_;
    my $self = {};
    $self->{$_} = $args{$_} for keys %args;
    bless $self, __PACKAGE__;
}

# static
sub o {
    shift if $_[0] eq __PACKAGE__;

    Fish::Youtube::Anon->new(@_);
}

sub AUTOLOAD {
    my $self = shift;
    ref $self or die;

    my $name = $AUTOLOAD;
    $name =~ s/.*://;

    exists $self->{$name} or die "Invalid property in anonymous class: ", $name, "\n";

    return @_ ? $self->{$name} = shift : $self->{$name};
}

1;
