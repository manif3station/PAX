requires 'JSON::PP';

recommends 'JSON::XS';

on test => sub {
    requires 'Test::More';
};
