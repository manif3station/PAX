use strict;
use warnings;
use Test::More;
use File::Path qw(make_path remove_tree);
use File::Spec;
use File::Temp qw(tempdir);
use FindBin;
use lib "$FindBin::Bin/../lib";

use PAX::StandaloneAnalysis;

=pod

=head1 NAME

t/standalone_analysis.t - standalone dependency closure regression tests

=head1 DESCRIPTION

This file validates that standalone dependency analysis follows transitive
Perl module references so bundled runtime payloads remain closed over the
module graph discovered from the application and its packaged dependencies.

=cut

my $root = tempdir('pax-standalone-analysis-XXXXXX', TMPDIR => 1, CLEANUP => 1);
my $lib_root = File::Spec->catdir($root, 'lib');
make_path(File::Spec->catdir($lib_root, 'Example', 'Transitive'));

my $entry_module = File::Spec->catfile($lib_root, 'Example', 'Transitive', 'Entry.pm');
my $mid_module = File::Spec->catfile($lib_root, 'Example', 'Transitive', 'Mid.pm');
my $leaf_module = File::Spec->catfile($lib_root, 'Example', 'Transitive', 'Leaf.pm');

open my $entry_fh, '>', $entry_module or die "cannot write entry module: $!";
print {$entry_fh} <<'PERL';
package Example::Transitive::Entry;
use strict;
use warnings;
use Example::Transitive::Mid ();
1;
PERL
close $entry_fh;

open my $mid_fh, '>', $mid_module or die "cannot write mid module: $!";
print {$mid_fh} <<'PERL';
package Example::Transitive::Mid;
use strict;
use warnings;
use Example::Transitive::Leaf ();
1;
PERL
close $mid_fh;

open my $leaf_fh, '>', $leaf_module or die "cannot write leaf module: $!";
print {$leaf_fh} <<'PERL';
package Example::Transitive::Leaf;
use strict;
use warnings;
1;
PERL
close $leaf_fh;

my $analysis = PAX::StandaloneAnalysis->new;
my $deps;
{
    local @INC = ($lib_root, @INC);
    $deps = $analysis->dependencies(
        entrypoint => $entry_module,
        code_units => [
            {
                source_path => $entry_module,
                unit_kind => 'lib',
                package => 'Example::Transitive::Entry',
                packaging => 'compiled_pcu_v1',
            },
        ],
        cpanfiles => [],
    );
}

my %modules = map { ($_->{module} => $_) } @{ $deps->{items} || [] };
ok($modules{'Example::Transitive::Mid'}, 'dependency analysis includes direct module reference');
ok($modules{'Example::Transitive::Leaf'}, 'dependency analysis includes transitive module reference');
is($modules{'Example::Transitive::Leaf'}{class}, 'bundled_pure_perl', 'transitive dependency is packaged as bundled pure-Perl runtime payload');

done_testing;
