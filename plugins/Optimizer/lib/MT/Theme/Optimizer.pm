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
@EXPORT_OK = qw( analyze_template analyze_mapping optimize commit );

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

sub optimize {
    my $self = shift;
    my ($rule, $tmpl_id, $map_id) = @_;

    my $tmpl = $self->{'template_queue'}->{$tmpl_id};
    $tmpl = $self->{'template_queue'}->{$tmpl_id} = MT->model('template')->load( $tmpl_id ) unless $tmpl;

    my ($map, $rule_ref, $message);
    if ($map_id) {
        $map = $self->{'mapping_queue'}->{$map_id};
        $map = $self->{'mapping_queue'}->{$map_id} = MT->model('templatemap')->load( $map_id ) unless $map;
        $rule_ref = $self->{'app'}->registry('optimizations')->{'mappings'}->{ $rule };
        $message  = "Applying optimization rule ".$rule." to archive mapping ".$map->archive_type." for ".$tmpl->name;
    } else {
        $rule_ref = $self->{'app'}->registry('optimizations')->{'templates'}->{ $rule };
        $message = "Applying optimization rule '".$rule."' to ".$tmpl->name;
    }
    # Apply handler
    if ( my $handler = $rule_ref->{'handler'} ) {
        if ( !ref($handler) ) {
            $self->_log("Handler found: " . $handler);
            $handler = $rule_ref->{'handler'} = $self->{'app'}->handler_to_coderef($handler);
        }
        $self->_log( $message );
        $handler->( $tmpl, $map );
    }
}


sub commit {
    my $self = shift;
    $self->_log("Saving all collected changes to templates.");
    foreach my $tmpl_id ( keys %{ $self->{'template_queue'} } ) {
        $self->{'template_queue'}->{$tmpl_id}->save() or 
            $self->_log("Template Optimizer could not save template #".$tmpl_id);
    }
    $self->_log("Saving all collected changes to template mappings.");
    foreach my $map_id ( keys %{ $self->{'mapping_queue'} } ) {
        $self->{'mapping_queue'}->{$map_id}->save() or 
            $self->_log("Template Optimizer could not save template mapping #".$map_id);
    }
}

sub _log {
    my $self = shift;
    $self->{'logger'}( $_[0] . "\n") if $self->{'verbose'};
}

1;
__END__
