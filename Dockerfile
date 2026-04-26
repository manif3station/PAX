FROM perl:5.42.0

ENV PAX_TARGET_PERL_FAMILY=5.42.x

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        gcc \
        jq \
        make \
    && rm -rf /var/lib/apt/lists/* \
    && perl -MConfig -E 'die "expected Perl 5.42.x\n" unless $Config{version} =~ /^5\.42\./; say "perl=$Config{version}"' \
    && cc --version

WORKDIR /workspace

CMD ["make", "test"]
