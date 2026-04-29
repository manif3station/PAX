#!/usr/bin/env perl
use strict;
use warnings;

use File::Find ();
use File::Spec;

my @perl_files = _perl_files();
my %changed = _semantic_changed_perl_files();
my @always = qw(bin/pax lib/PAX.pm);
my %always = map { $_ => 1 } @always;
my @errors;

for my $path (@perl_files) {
    my $content = _slurp($path);
    push @errors, "$path missing =head1 NAME"
        if $content !~ /^=head1 NAME\b/m;
    if (_is_module($path)) {
        push @errors, "$path missing descriptive POD section"
            if $content !~ /^=head1 (?:DESCRIPTION|INTRODUCTION|SYNOPSIS|PURPOSE)\b/m;
    }
    elsif (_is_test($path)) {
        push @errors, "$path missing =head1 DESCRIPTION"
            if $content !~ /^=head1 DESCRIPTION\b/m;
    }
    else {
        push @errors, "$path missing synopsis or description POD"
            if $content !~ /^=head1 (?:SYNOPSIS|DESCRIPTION|PURPOSE)\b/m;
    }

    my @subs = _changed_named_subs($path, \%changed);
    next if !@subs;
    my %seen_comment;
    my @lines = split /\n/, $content, -1;
    for my $sub (@subs) {
        my $comment = _sub_comment(\@lines, $sub->{line});
        if (!defined $comment) {
            push @errors, sprintf('%s sub %s missing preceding comment', $path, $sub->{name});
            next;
        }
        if ($comment =~ /\A(?:helper|internal helper|utility|constructor|accessor|method|function|subroutine)\b/i) {
            push @errors, sprintf('%s sub %s uses boilerplate comment "%s"', $path, $sub->{name}, $comment);
            next;
        }
        if ($comment !~ /[A-Za-z].*[A-Za-z].*[A-Za-z]/) {
            push @errors, sprintf('%s sub %s comment too thin "%s"', $path, $sub->{name}, $comment);
            next;
        }
        if ($seen_comment{$comment}++) {
            push @errors, sprintf('%s sub %s reuses duplicate comment "%s"', $path, $sub->{name}, $comment);
        }
    }
}

if (@errors) {
    print STDERR "POD-DOC-ALL failed:\n";
    print STDERR " - $_\n" for @errors;
    exit 1;
}

print "POD-DOC-ALL: maintained Perl files carry current POD and changed subroutines carry non-boilerplate comments\n";

# Gather every Perl asset the documentation gate treats as part of the
# maintained code surface.
sub _perl_files {
    my @files;
    push @files, 'bin/pax' if -f 'bin/pax';
    my @roots = grep { -d $_ } qw(lib t tools);
    File::Find::find(
        sub {
            if (-d $_) {
                if (_skip_tree(File::Spec->abs2rel($File::Find::name, '.'))) {
                    $File::Find::prune = 1;
                }
                return;
            }
            my $path = File::Spec->abs2rel($File::Find::name, '.');
            return if _skip_tree($path);
            push @files, $path
                if $path =~ m{\Alib/.*\.pm\z}
                || $path =~ m{\At/.*\.t\z}
                || $path =~ m{\At/.*\.pl\z}
                || $path =~ m{\Atools/.*\.pl\z};
        },
        @roots,
    );
    return @files;
}

# Skip generated, excluded, or copied trees that are not part of the maintained
# repository Perl surface.
sub _skip_tree {
    my ($path) = @_;
    return 1 if !defined $path || $path eq '.';
    return 1 if $path =~ m{\APAX-\d};
    return 1 if $path =~ m{\ADD Source Code(?:/|\z)};
    return 1 if $path =~ m{\At/tmp};
    return 1 if $path =~ m{\A(?:cover_db|projects|project|examples|pax-webapp)(?:/|\z)};
    return 0;
}

# Focus enforcement on files with real behavior or documentation changes, not
# pure version-line churn.
sub _semantic_changed_perl_files {
    my @targets = grep { -f $_ } ('bin/pax');
    push @targets, map { File::Spec->abs2rel($_, '.') } glob('lib/PAX/**/*.pm');
    push @targets, map { File::Spec->abs2rel($_, '.') } glob('lib/PAX/*.pm');
    push @targets, map { File::Spec->abs2rel($_, '.') } glob('t/*.t');
    push @targets, map { File::Spec->abs2rel($_, '.') } glob('tools/*.pl');
    my %targets = map { $_ => 1 } @targets;

    my @name_cmd = ('git', 'diff', '--name-only');
    push @name_cmd, 'HEAD^', 'HEAD' if _clean_tree() && _has_head_parent();
    my @changed = grep { $targets{$_} } split /\n/, _capture(@name_cmd);

    my %semantic;
    for my $path (@changed) {
        my @diff_cmd = ('git', 'diff', '--unified=0');
        push @diff_cmd, 'HEAD^', 'HEAD' if _clean_tree() && _has_head_parent();
        push @diff_cmd, '--', $path;
        my $diff = _capture(@diff_cmd);
        my @meaningful = grep {
            /^[+-]/ &&
            !/^(?:\+\+\+|---)/ &&
            !/^[+-]\s*$/ &&
            !/^[+-]\s*(?:our\s+)?\$VERSION\b/ &&
            !/^[+-]\s*version\s*=/ &&
            !/^[+-]\s*0\.\d+/
        } split /\n/, $diff;
        $semantic{$path} = 1 if @meaningful;
    }
    return %semantic;
}

# Limit subroutine-comment enforcement to newly touched named subs in the
# current semantic change set.
sub _changed_named_subs {
    my ($path, $changed) = @_;
    return if !$changed->{$path};
    my @diff_cmd = ('git', 'diff', '--unified=0');
    push @diff_cmd, 'HEAD^', 'HEAD' if _clean_tree() && _has_head_parent();
    push @diff_cmd, '--', $path;
    my $diff = _capture(@diff_cmd);
    my %names;
    my @subs;
    for my $line (split /\n/, $diff) {
        next if $line !~ /^\+.*\bsub\s+([A-Za-z_]\w*)\b/;
        my $name = $1;
        next if $names{$name}++;
        my $line_no = _find_sub_line($path, $name);
        push @subs, { name => $name, line => $line_no } if $line_no;
    }
    return @subs;
}

# Resolve the live source line for a named subroutine so comment lookup can
# inspect the current file rather than the patch hunk.
sub _find_sub_line {
    my ($path, $name) = @_;
    my @lines = split /\n/, _slurp($path), -1;
    for my $idx (0 .. $#lines) {
        return $idx + 1 if $lines[$idx] =~ /^sub\s+\Q$name\E\b/;
    }
    return;
}

# Read the contiguous preceding comment block that documents a subroutine.
sub _sub_comment {
    my ($lines, $line_no) = @_;
    my @comments;
    for (my $idx = $line_no - 2; $idx >= 0; $idx--) {
        my $line = $lines->[$idx];
        last if !defined $line;
        next if $line =~ /^\s*$/ && !@comments;
        if ($line =~ /^\s*#\s?(.*\S)\s*$/) {
            unshift @comments, $1;
            next;
        }
        last;
    }
    return if !@comments;
    return join ' ', @comments;
}

# Classify a path as a Perl module.
sub _is_module { $_[0] =~ /\.pm\z/ }

# Classify a path as a Perl test file.
sub _is_test   { $_[0] =~ m{\At/.*\.t\z} }

# Read a full file into memory for lightweight structural checks.
sub _slurp {
    my ($path) = @_;
    open my $fh, '<', $path or die "open $path: $!";
    local $/;
    my $content = <$fh>;
    close $fh;
    return $content;
}

# Capture command output without shell interpolation so the gate stays
# deterministic across git invocations.
sub _capture {
    my @cmd = @_;
    my $pid = open my $fh, '-|', @cmd or die "exec @cmd: $!";
    local $/;
    my $out = <$fh> // '';
    close $fh;
    return $out;
}

# Cache working-tree cleanliness because the gate asks for it several times
# while building git diff commands.
sub _clean_tree {
    our $clean_cache;
    return $clean_cache if defined $clean_cache;
    my $dirty = _capture('git', 'status', '--short');
    $clean_cache = $dirty eq '' ? 1 : 0;
    return $clean_cache;
}

# Detect whether HEAD^ exists so the gate can compare committed changes when the
# tree is already clean.
sub _has_head_parent {
    our $has_parent_cache;
    return $has_parent_cache if defined $has_parent_cache;
    _capture('git', 'rev-parse', '--verify', 'HEAD^');
    $has_parent_cache = $? == 0 ? 1 : 0;
    return $has_parent_cache;
}

__END__

=head1 NAME

pod_doc_all.pl - enforce repository-wide POD and subroutine-comment coverage

=head1 SYNOPSIS

  perl tools/pod_doc_all.pl

=head1 DESCRIPTION

This script is the strict documentation completeness check behind the PAX doc
gate.

It inspects maintained Perl assets in C<bin/>, C<lib/>, C<t/>, and C<tools/>
and verifies that every in-scope file carries current file-level POD. It also
verifies that changed named subroutines carry unique, non-boilerplate preceding
comments so behavior changes do not outrun their local documentation.

The file-level coverage check spans the full maintained Perl surface. The
subroutine-comment check intentionally ignores pure version-line churn and
focuses on semantic changes in the current tree or the most recent committed
diff.
