use strict;
use warnings;
no warnings 'once';
use Test::More;
use File::Spec;
use File::Temp qw(tempdir);
use FindBin;
use lib "$FindBin::Bin/../lib";

use PAX::StandaloneRuntime ();

=pod

=head1 NAME

t/cov_r2srt_runtime_gaps.t - last coverage gaps of the standalone runtime

=head1 DESCRIPTION

Exercises the small whole-file reader helper, the simple template renderer when
the reader fails or the template is empty, and a compiled handler installed
under a prototype.

=head1 WHY IT EXISTS

The earlier coverage tests left these defensive outcomes unreached after the
redundant guards were removed from the runtime. Keeping them here proves each
remaining outcome is real and reachable.

=cut

my $dir = tempdir('pax-cov-r2srt-XXXXXX', TMPDIR => 1, CLEANUP => 1);
my $P = 'PAX::StandaloneRuntime';

# write_file($path, $text)
# Writes a fixture file. Input: path and text. Output: the path.
sub write_file {
    my ($path, $text) = @_;
    open my $fh, '>', $path or die "cannot write $path: $!";
    print {$fh} $text;
    close $fh;
    return $path;
}

# _slurp_file reads whole files and dies with the path on failure
{
    my $path = write_file("$dir/a.txt", "one\ntwo\n");
    is(PAX::StandaloneRuntime::_slurp_file($path), "one\ntwo\n", 'slurp returns the whole file');
    my $ok = eval { PAX::StandaloneRuntime::_slurp_file("$dir/none.txt"); 1 };
    like($@, qr/Unable to read \Q$dir\E\/none\.txt/, 'slurp dies naming the missing file') if !$ok;
    ok(!$ok, 'slurp of a missing file fails');
}

# the template renderer tolerates a failing or empty read
{
    my $tpl = write_file("$dir/t.tpl", 'hi [% who %]!');
    is(PAX::StandaloneRuntime::_render_simple_template_asset($tpl, { who => 'you' }), 'hi you!', 'template renders');
    my $empty = write_file("$dir/empty.tpl", '');
    is(PAX::StandaloneRuntime::_render_simple_template_asset($empty, {}), undef, 'empty template renders as undef');
    no warnings 'redefine';
    local *PAX::StandaloneRuntime::_slurp_file = sub { die "boom\n" };
    is(PAX::StandaloneRuntime::_render_simple_template_asset($tpl, {}), undef, 'an unreadable template renders as undef');
}

# a handler installed under a prototype is reachable and honors the prototype
{
    my $pkg = 'PaxCovR2srtProto';
    PAX::StandaloneRuntime::_install_sub_impl($pkg, 'adder', '($$)', sub { return $_[0] + $_[1] });
    no strict 'refs';
    is(&{"${pkg}::adder"}(2, 3), 5, 'prototyped install calls the implementation');
    is(prototype("${pkg}::adder"), '$$', 'prototype kept');
}

done_testing;
