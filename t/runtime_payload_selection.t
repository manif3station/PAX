use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/../lib";

use PAX::StandaloneImage;

my $have_plack = eval {
    require Plack::Middleware::FixMissingBodyInRedirect;
    1;
};

SKIP: {
    skip 'Plack web stack not installed', 3 if !$have_plack;

    my @inc_dirs = PAX::StandaloneImage::_runtime_inc_dirs([]);
    my @loaded = PAX::StandaloneImage::_probe_loaded_runtime_files(
        modules => ['Plack::Middleware::FixMissingBodyInRedirect'],
        lib_dirs => [],
    );

    my ($html_parser_pm) = grep { /HTML\/Parser\.pm$/ } @loaded;
    ok($html_parser_pm, 'runtime probe loads HTML::Parser wrapper');

    my @xs = PAX::StandaloneImage::_related_xs_files_for_source($html_parser_pm, \@inc_dirs);
    ok((grep { /auto\/HTML\/Parser\/Parser\.(?:so|bundle|dll)$/ } @xs) >= 1, 'runtime payload discovery includes matching HTML::Parser XS binary');

    my %selected = map { $_ => 1 } PAX::StandaloneImage::_runtime_selected_files(
        inc_dirs => \@inc_dirs,
        dependencies => [],
        lib_dirs => [],
        exclude_files => [],
    );
    ok($selected{$html_parser_pm}, 'runtime selection includes probe-discovered HTML::Parser wrapper without needing an explicit dependency entry');
}

done_testing;

=pod

=head1 NAME

t/runtime_payload_selection.t - cover the runtime payload selection behavior exercised by the PAX test suite.

=head1 DESCRIPTION

This file is part of the maintained PAX Perl surface and exists to cover the runtime payload selection behavior exercised by the PAX test suite.

=cut

