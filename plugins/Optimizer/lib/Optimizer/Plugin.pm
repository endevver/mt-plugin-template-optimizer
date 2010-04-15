package Optimizer::Plugin;

use strict;
use MT::Theme::Optimizer;

sub optimize_start {
    my ($app,$type) = @_;
    $app->validate_magic or return;
    my $param ||= {};

    my $optimizer = MT::Theme::Optimizer->new({
        app     => $app,
        verbose => 1,
        logger  => sub { MT->log( $_[0] ); }
    });

    my @loop;
    my @blogs = $app->param('id');
    my $count = 0;
    for my $blog_id (@blogs) {
        my $blog = MT->model('blog')->load($blog_id) or next;
        my @tmpls = MT->model('template')->load({ blog_id => $blog_id, type => { not => 'backup' } });
        for my $tmpl (@tmpls) {
            next unless $tmpl;
            my $recs = $optimizer->analyze_template( $tmpl );
            for my $recommendation (@$recs) {
                push @loop, {
                    '__first__'     => 0,
                    '__last__'      => 0,
                    '__even__'      => ($count / 2 == 0),
                    '__odd__'       => ($count / 2 == 1),
                    '__counter__'   => ($count + 1),
                    'template_id'   => $tmpl->id,
                    'template_name' => $tmpl->name,
                    'key'           => $tmpl->id,
                    'blog_id'       => $blog->id,
                    'blog_name'     => $blog->name,
                    %$recommendation
                };
                $count++;
            }
            if ($tmpl->type =~ /^(individual|archive)$/i) {
                my @maps = MT->model('templatemap')->load({ template_id => $tmpl->id });
                for my $map (@maps) {
                    my $recs = $optimizer->analyze_mapping( $tmpl, $map );
                    for my $recommendation (@$recs) {
                        push @loop, {
                            '__first__'     => 0,
                            '__last__'      => 0,
                            '__even__'      => ($count / 2 == 0),
                            '__odd__'       => ($count / 2 == 1),
                            '__counter__'   => ($count + 1),
                            'template_id'   => $tmpl->id,
                            'template_name' => $tmpl->name,
                            'key'           => $tmpl->id . ":" . $map->id,
                            'blog_id'       => $blog->id,
                            'blog_name'     => $blog->name,
                            %$recommendation
                        };
                        $count++;
                    }
                }
            }
        }
    }
    $loop[0]->{'__first__'} = 1;
    $loop[ $#loop ]->{'__last__'} = 1;

    $param->{recommend_loop} = \@loop;
    $param->{screen_id}      = 'optimize';
    $param->{return_args}    = $app->return_args;
    return $app->load_tmpl( 'start.tmpl', $param );
}

sub optimize {
    my ($app) = @_;
    $app->validate_magic or return;

    my $optimizer = MT::Theme::Optimizer->new({
        app     => $app,
        verbose => 1,
        logger  => sub { MT->log( $_[0] ); }
    });

    my @rules = $app->param('id');
    my $count = 0;
    my %templates;
    my %mappings;
    for my $rule_key (@rules) {
        my ($rule, @objs) = split(':',$rule_key);
        my ($tmpl_id, $map_id) = @objs;
        my $tmpl = $templates{$tmpl_id};
        $tmpl = $templates{$tmpl_id} = MT->model('template')->load( $tmpl_id ) unless $tmpl;
        my ($map, $rule_ref, $message);
        if ($map_id) {
            $map = $mappings{$map_id};
            $map = $mappings{$map_id} = MT->model('templatemap')->load( $map_id ) unless $map;
            $rule_ref = $app->registry('optimizations')->{'mappings'}->{ $rule };
            $message  = "Applying optimization rule ".$rule." to archive mapping ".$map->archive_type." for ".$tmpl->name;
        } else {
            $rule_ref = $app->registry('optimizations')->{'templates'}->{ $rule };
            $message = "Applying optimization rule '".$rule."' to ".$tmpl->name;
        }
        # Apply handler
        if ( my $handler = $rule_ref->{'handler'} ) {
            if ( !ref($handler) ) {
                MT->log("Handler found: " . $handler);
                $handler = $rule_ref->{'handler'} = $app->handler_to_coderef($handler);
            }
            MT->log({ blog_id => $tmpl->id, message => $message });
            $handler->( $tmpl, $map );
        }
    }
    MT->log("Saving all collected changes to templates.");
    foreach my $tmpl_id ( keys %templates ) {
        $templates{$tmpl_id}->save() or 
            MT->log("Template Optimizer could not save template #".$tmpl_id);
    }
    MT->log("Saving all collected changes to template mappings.");
    foreach my $map_id ( keys %mappings ) {
        $mappings{$map_id}->save() or 
            MT->log("Template Optimizer could not save template mapping #".$map_id);
    }
    $app->add_return_arg( optimizations_applied => 1 );
    $app->call_return;
}

1;
__END__
