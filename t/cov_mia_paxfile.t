use strict;
use warnings;
use Test::More;
use File::Temp qw(tempdir);
use FindBin;
use lib "$FindBin::Bin/../lib";

use PAX::Paxfile;

=pod

=head1 NAME

t/cov_mia_paxfile.t - coverage tests for PAX::Paxfile

=head1 DESCRIPTION

Exercises the paxfile.yml parser with fabricated files: scalar keys, quoted
values, list sections, comments, CRLF endings, repeated sections, and every
error path.

=head1 WHY IT EXISTS

Keeps the parser's branches and conditions fully covered so regressions in the
tiny YAML subset are caught.

=cut

my $dir = tempdir('pax-cov-mia-paxfile-XXXXXX', TMPDIR => 1, CLEANUP => 1);

# write_file($name, $text)
# Writes a fixture file inside the temp dir and returns its path.
# Input: file name and raw bytes. Output: path.
sub write_file {
    my ($name, $text) = @_;
    my $path = "$dir/$name";
    open my $fh, '>:raw', $path or die "cannot write $path: $!";
    print {$fh} $text;
    close $fh;
    return $path;
}

my $full = write_file('full.yml',
    "# leading comment\r\n"
  . "\r\n"
  . "name: demo   # trailing comment\r\n"
  . "quoted: \"double value\"\n"
  . "single: 'single value'\n"
  . "plain-key_2:   spaced  \n"
  . "libs:\n"
  . "  - lib\n"
  . "  - \"quoted lib\"\n"
  . "libs:\n"
  . "  - extra\n"
  . "empty:\n"
  . "after: 1\n"
);
my $data = PAX::Paxfile->load($full);
is_deeply($data, {
    name => 'demo',
    quoted => 'double value',
    single => 'single value',
    'plain-key_2' => 'spaced',
    libs => [ 'lib', 'quoted lib', 'extra' ],
    empty => [],
    after => '1',
}, 'load parses scalars, quotes, comments, CRLF and repeated list sections');

is_deeply(PAX::Paxfile->load_optional("$dir/absent.yml"), {}, 'load_optional returns empty hash for a missing file');
is_deeply(PAX::Paxfile->load_optional($full), $data, 'load_optional loads an existing file');

{
    my $cwd_dir = tempdir('pax-cov-mia-paxfile-cwd-XXXXXX', TMPDIR => 1, CLEANUP => 1);
    open my $fh, '>', "$cwd_dir/paxfile.yml" or die $!;
    print {$fh} "default: yes\n";
    close $fh;
    require Cwd;
    my $old = Cwd::getcwd();
    chdir $cwd_dir or die $!;
    my $got = PAX::Paxfile->load_optional;
    chdir $old or die $!;
    is_deeply($got, { default => 'yes' }, 'load_optional defaults to ./paxfile.yml');
}

eval { PAX::Paxfile->load("$dir/absent.yml") };
like($@, qr/cannot read .*absent\.yml/, 'load dies when the file cannot be opened');

my $orphan = write_file('orphan.yml', "key: v\n  - item\n");
eval { PAX::Paxfile->load($orphan) };
like($@, qr/unsupported paxfile\.yml syntax:\s+- item/, 'list item after a scalar key is rejected');

my $nosection = write_file('nosection.yml', "- item\n");
eval { PAX::Paxfile->load($nosection) };
like($@, qr/unsupported paxfile\.yml syntax/, 'list item before any section is rejected');

my $garbage = write_file('garbage.yml', "!!! nonsense\n");
eval { PAX::Paxfile->load($garbage) };
like($@, qr/unsupported paxfile\.yml syntax: !!! nonsense/, 'unparseable line is rejected');

my $badinsec = write_file('badinsec.yml', "libs:\n  - ok\n  not a list item\n");
eval { PAX::Paxfile->load($badinsec) };
like($@, qr/unsupported paxfile\.yml syntax:\s+not a list item/, 'garbage inside a section is rejected');

is(PAX::Paxfile::_scalar('  "mismatch'), '"mismatch', '_scalar leaves unbalanced quotes alone');

done_testing;
