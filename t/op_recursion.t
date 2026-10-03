use strict;
use warnings;
use Test::More;
use File::Path qw(make_path);
use File::Temp qw(tempdir);
use FindBin;
use lib "$FindBin::Bin/../lib";

use PAX::StandaloneRuntime;

=pod

=head1 NAME

t/op_recursion.t - recursive compiled-sub handlers actually recurse

=head1 WHY IT EXISTS

Compiled-sub handlers are hand-written replicas that are compiled lazily, so a
mistake in one only shows when the sub runs. Handlers that call themselves
(nested config merge, .env comment stripping, skill command collection, XML
payload decoding) once died at run time with "Undefined subroutine __SUB__" and
"Can't use an undefined value as a subroutine reference", which broke layered
.env files and layered config in the standalone binary only.

=head1 DESCRIPTION

Each handler is installed through the real lazy loader and called with input
that forces at least one level of recursion.

=head1 HOW TO RUN

  prove -l t/op_recursion.t

=cut

my $T = tempdir('pax-op-rec-XXXXXX', TMPDIR => 1, CLEANUP => 1);

# .env block comments recurse once per comment boundary.
{
    PAX::StandaloneRuntime::_install_compiled_sub('PaxOpRecEnv', { name => '_strip_env_comments', op => 'env_strip_comments' });
    my $in_block = 0;
    my @out = map {
        PaxOpRecEnv->_strip_env_comments(line => $_, file => 'f', line_no => 1, in_block_comment => \$in_block)
    } ('A=1', '/* start', 'inside', 'end */ B=2', '// gone', '# gone', '/* one */ C=3');
    is_deeply(\@out, [ 'A=1', '', '', ' B=2', '', '', ' C=3' ], 'block comments are stripped through recursion');
    is($in_block, 0, 'block comment state is closed again');
    eval { PaxOpRecEnv->_strip_env_comments(line => 'x') };
    like($@, qr/Missing in_block_comment state/, 'missing state still dies');
}

# Nested hashes merge through the method itself.
for my $case (
    [ 'config_merge_hashes', 'PaxOpRecCfg', 'merge_named_array_method' ],
    [ 'skill_dispatcher_merge_skill_hashes', 'PaxOpRecSkill', 'merge_array_items_method' ],
) {
    my ($op, $package, $key) = @$case;
    no strict 'refs';
    *{"${package}::_arrays"} = sub { return [ @{ $_[1] }, @{ $_[2] } ] };
    PAX::StandaloneRuntime::_install_compiled_sub($package, { name => '_merge_hashes', op => $op, $key => "${package}::_arrays" });
    my $merged = $package->_merge_hashes(
        { web => { port => 1, host => 'h' }, keep => 'left' },
        { web => { port => 2 }, add => 'right' },
    );
    is_deeply($merged, { web => { port => 2, host => 'h' }, keep => 'left', add => 'right' }, "$op merges nested hashes");
}

# Skill command collection descends into nested skill directories.
{
    make_path("$T/skill/skills/child");
    no strict 'refs';
    *{'PaxOpRecSug::_logical'} = sub { return $_[0] };
    PAX::StandaloneRuntime::_install_compiled_sub('PaxOpRecSug', { name => '_collect', op => 'suggest_collect_skill_commands', logical_name_method => 'PaxOpRecSug::_logical' });
    my @entries = PaxOpRecSug->_collect("$T/skill", 'top');
    is_deeply(\@entries, [], 'nested skill directories are walked without error');
}

# XML payloads decode nested elements.
{
    PAX::StandaloneRuntime::_install_compiled_sub('PaxOpRecXml', { name => '_payload', op => 'query_xml_element_payload' });
    my $node = PaxOpRecXml::_payload([ {}, a => [ {}, 0 => 'text' ], b => [ { id => 1 }, c => [ {}, 0 => 'x' ], c => [ {}, 0 => 'y' ] ] ]);
    is_deeply($node, { a => 'text', b => { _attributes => { id => 1 }, c => [ 'x', 'y' ] } }, 'nested XML elements decode through __SUB__');
}

# A lazily compiled sub may be called for the first time as a sort comparator, where perl
# forbids `goto &sub`; the stubs must forward with an ordinary call.
{
    PAX::StandaloneRuntime::_install_compiled_sub_lazily('PaxOpRecSort', { name => 'tie', op => 'return_literal', value_type => 'number', value => 0 });
    PAX::StandaloneRuntime::_install_compiled_sub_lazily('PaxOpRecSort', { name => 'tie_proto', op => 'return_literal', value_type => 'number', value => 0, prototype => '($$)' });
    for my $comparator (qw(PaxOpRecSort::tie PaxOpRecSort::tie_proto)) {
        no strict 'refs';
        my @sorted = eval { sort $comparator (3, 1, 2) };
        is($@, '', "a stub used as a sort comparator ($comparator) does not goto");
        is(scalar(@sorted), 3, "the sort over $comparator completes");
    }
}

# Handler text is compiled inside the runtime package, so __PACKAGE__ there names the runtime,
# not the application package the sub belongs to; handlers must use the $package they are given.
{
    open my $rt, '<', "$FindBin::Bin/../lib/PAX/StandaloneRuntime.pm" or die "cannot read runtime: $!";
    my $text = do { local $/; <$rt> };
    close $rt;
    my ($handlers) = $text =~ /\n__DATA__\n(.*)\z/s;
    unlike($handlers // '', qr/__PACKAGE__/, 'op handlers never use __PACKAGE__ (it is the runtime package inside a handler)');
}

done_testing();
