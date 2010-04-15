# (C) 2010 Endevver LLC. All Rights Reserved.
# This code is licensed under the GPL v2.

package MT::Theme::Optimizer;

use MT;
use Carp;
use strict;
use vars qw( @EXPORT_OK );

# We are exporting functions
use base qw/Exporter/;
# Export list - to allow fine tuning of export table
@EXPORT_OK = qw( analyze_template analyze_mapping optimize );

sub DESTROY { }

$SIG{INT} = sub { die "Interrupted\n"; };

$| = 1;    # autoflush

sub new {
    my $class  = shift;
    my $params = shift;
    my $self   = {};
    foreach my $prop (qw( verbose logger app )) {
        if ( exists $params->{$prop} ) {
            $self->{$prop} = $params->{$prop};
        }
    }
    $self->{'app'}              ||= MT->new() or die MT->errstr;
    $self->{'logger'}           ||= sub { },
    $self->{'verbose'}          ||= 0,

    bless $self, $class;
    return $self;
}

sub optimize {
    my $self = shift;
}

sub _process {
    my $self = shift;
    my $opts = shift;
    my $app  = $self->{'app'};
    my @findings;
    foreach my $optname ( sort { 
        $opts->{$a}->{order} ||= 999; 
        $opts->{$b}->{order} ||= 999; 
        return $opts->{$a}->{order} <=> $opts->{$b}->{order}
                          } keys %$opts ) {
        my $o = $opts->{$optname};
        next unless $o->{label};
        my $label = &{$o->{label}};
        if ( my $cond = $o->{condition} ) {
            if ( !ref($cond) ) {
                $cond = $o->{condition} = $app->handler_to_coderef($cond);
            }
            next unless $cond->( @_ );
        }
        my $desc;
        if ( my $handler = $o->{short_description} ) {
            if ( !ref($handler) ) {
                $handler = $o->{short_description} = $app->handler_to_coderef($handler);
            }
            $desc = $handler->( @_ );
        }
        $self->_log( "Analyzing " . $_[0]->name . " for '" . $label . "' optimization." );
        push @findings, {
            type        => $optname,
            label       => $label,
            description => $desc
        };
        last if ($o->{last});
    }
    return \@findings;
}

sub analyze_mapping {
    my $self = shift;
    my ($tmpl,$map) = @_;
    my $opts = $self->{'app'}->registry('optimizations')->{'mappings'};
    return $self->_process( $opts, $tmpl, $map );
}

sub analyze_template {
    my $self = shift;
    my ($tmpl) = @_;
    my $opts = $self->{'app'}->registry('optimizations')->{'templates'};
    return $self->_process( $opts, $tmpl );
}

sub _log {
    my $self = shift;
    $self->{'logger'}( $_[0] . "\n") if $self->{'verbose'};
}

1;
__END__
