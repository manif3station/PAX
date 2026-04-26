package Example::PaxWeb;

use strict;
use warnings;

use Dancer2 appname => 'PaxWeb';
use File::Spec;
use Template;

our $VERSION = '0.1.0';
our $ASSET_ROOT;

sub build_psgi_app {
    my ($class, %args) = @_;
    $ASSET_ROOT = $args{asset_root} // die "asset_root required";

    my $views = File::Spec->catdir($ASSET_ROOT, 'views');
    my $public = File::Spec->catdir($ASSET_ROOT, 'public');

    set serializer => 'Mutable';
    set views => $views;
    set public_dir => $public;

    my $tt = Template->new(
        INCLUDE_PATH => [$views],
        ABSOLUTE => 1,
        RELATIVE => 1,
    );

    get '/' => sub {
        my $html = q{};
        $tt->process('index.tt', {
            title => 'PAX Web App',
            headline => 'Standalone Perl Web Application',
            asset_root => $ASSET_ROOT,
        }, \$html) or die $tt->error;
        return send_as html => $html;
    };

    get '/healthz' => sub {
        status 200;
        return {
            ok => 1,
            framework => 'Dancer2',
            server => 'Starman',
            template => 'TemplateToolkit',
            asset_root => $ASSET_ROOT,
        };
    };

    return dancer_app->to_app;
}

1;
