use strict; use warnings;
use Developer::Dashboard::PathRegistry;
use Developer::Dashboard::FileRegistry;
use Developer::Dashboard::Auth;
use Digest::MD5 qw(md5_hex);
my $paths = Developer::Dashboard::PathRegistry->new(home => $ENV{HOME}, cwd => $ENV{HOME});
my $auth = Developer::Dashboard::Auth->new(paths => $paths, files => Developer::Dashboard::FileRegistry->new(paths => $paths));
# login_page: print the full text for several inputs
my @cases = ([], [message => 'Bad <login> & "stuff"'], [message => '', redirect_to => '/x?a=1&b=<2>"q"'], [redirect_to => undef], [message => '0'], [message => '$message $redirect_to', redirect_to => '$message @x \\n'], [message => "multi\nline"], [redirect_to => ''], [message => 'x', redirect_to => 0]);
my $i = 0;
for my $c (@cases) { $i++; my $page = $auth->login_page(@$c); utf8::encode(my $bytes = $page); print "--- page $i len=", length($page), " md5=", md5_hex($bytes), "\n"; print $page if $i <= 3 || $i == 6; }
# password hash
for my $a (['u','p','s'], ['','',''], ['user','pass word','salt:with:colons'], ["\xc3\xbc","p\xd0\xb0",'s'], ['a:b','c:d','e:f'], ['u','p',''], ['0','0','0']) {
    no warnings; print "hash(", join(',', map { length } @$a), ")=", $auth->_password_hash(@$a), "\n";
}
{ no warnings; print "hash_undef=", $auth->_password_hash(undef, undef, undef), "\n"; print "hash_short=", $auth->_password_hash('u'), "\n"; }
# resolve host ips (no network: literals and localhost only)
for my $h (undef, '', '127.0.0.1', '127.0.0.5', '::1', '0:0:0:0:0:0:0:1', 'localhost', '10.0.0.1', '8.8.8.8', '2001:db8::1', 'FE80::1', '0.0.0.0', '999.1.1.1', 'bq-no-such-host.invalid', '1.2.3', '::ffff:127.0.0.1', '127.1', '  ', 'a b') {
    my @ips = sort $auth->_resolve_host_ips($h);
    my $r = $auth->_host_resolves_only_to_loopback($h);
    print "resolve(", (defined $h ? "'$h'" : 'undef'), ")=", join('|', @ips), " loopback_only=", ($r ? 1 : 0), "\n";
}
my @l = $auth->_resolve_host_ips(); print "resolve_noarg=", scalar(@l), " only=", $auth->_host_resolves_only_to_loopback() ? 1 : 0, "\n";
my $scalar = $auth->_resolve_host_ips('127.0.0.1'); print "scalar_ctx=", (defined $scalar ? $scalar : 'undef'), "\n";
print "END\n";
