use strict; use warnings;
use Developer::Dashboard::PathRegistry;
use Developer::Dashboard::SessionStore;
use Developer::Dashboard::JSON qw(json_encode);
sub show { my ($l,$v)=@_; print "$l=", (defined $v ? (ref $v ? json_encode($v) : "'$v'") : 'undef'), "\n"; }
my $home = $ENV{HOME};
my $paths = Developer::Dashboard::PathRegistry->new(home => $home, cwd => $home);
my $store = Developer::Dashboard::SessionStore->new(paths => $paths);
show('del_undef', scalar $store->delete(undef));
show('del_empty', scalar $store->delete(''));
show('del_missing', scalar $store->delete('nosuchsession'));
my @list = $store->delete();
print "del_noarg_list=", scalar(@list), "\n";
my $s = $store->create(username => 'bq_user', role => 'admin', remote_addr => '1.2.3.4');
print "created_len=", length($s->{session_id}), " user=$s->{username} role=$s->{role}\n";
show('get_present', $store->get($s->{session_id}) ? 'yes' : 'no');
show('del_real', scalar $store->delete($s->{session_id}));
show('get_after', $store->get($s->{session_id}) ? 'yes' : 'no');
show('del_again', scalar $store->delete($s->{session_id}));
# unsafe ids must not delete outside the sessions root
my $root = $paths->sessions_root;
my $outside = "$root/../bq_outside.json";
open my $fh, '>', $outside or die; print $fh "{}"; close $fh;
show('del_traversal', scalar $store->delete('../bq_outside'));
print "outside_still_exists=", (-f $outside ? 1 : 0), "\n";
unlink $outside;
# an id with odd characters maps to a sanitized file
my ($f) = $store->_session_file_candidates('a/b c');
print "cand_tail=", ($f =~ s{.*/sessions/}{S/}r), "\n";
my @cands = $store->_session_file_candidates('x.y-z_1');
print "cand_count=", scalar(@cands), " tail=", ($cands[0] =~ s{.*/}{}r), "\n";
print "file_tail=", ($store->_session_file('..\\evil') =~ s{.*/}{}r), "\n";
print "file_undef_tail=", (eval { $store->_session_file(undef) } // 'died') =~ s{.*/}{}r, "\n";
open $fh, '>', "$root/a_b_c.json" or die; print $fh "{}"; close $fh;
show('del_sanitized', scalar $store->delete('a/b/c'));
print "sanitized_exists=", (-f "$root/a_b_c.json" ? 1 : 0), "\n";
unlink "$root/a_b_c.json";
