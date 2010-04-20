package MT::Theme::Optimizer::Rules;

use strict;

sub recent_ssi_handler {
    my ($tmpl) = @_;
    $tmpl->include_with_ssi( 1 ); 
    my $blog = $tmpl->blog();
    if ($blog->include_system eq '') {
        my $req = MT::Request->instance;
        unless ($req->stash('warned_about_ssi')) {
            MT->log({ blog_id => $blog->id,
                      message => 'In order to take advantage of certain template optimizations you need to turn on "Server Side Includes" in your blog preferences.' });
            $req->stash('warned_about_ssi',1);
        }
    }
}

sub recent_comments_handler {
    my ($tmpl) = @_;
    $tmpl->cache_expire_type( 2 ); 
    $tmpl->cache_expire_event('comment'); 

    my $blog = $tmpl->blog();
    unless ($blog->include_cache) {
        $blog->include_cache(1);
        $blog->save;
    }
}

sub recent_entries_handler {
    my ($tmpl) = @_;
    $tmpl->cache_expire_type( 2 ); 
    $tmpl->cache_expire_event('entry');

    my $blog = $tmpl->blog();
    unless ($blog->include_cache) {
        $blog->include_cache(1);
        $blog->save;
    }
}

1;
__END__
