PERL ?= perl
DOCKER ?= docker
PAX_IMAGE ?= pax-dev:perl-5.42
DIST_VERSION ?= $(shell $(PERL) -Ilib -MPAX -e "print \$$PAX::VERSION")
CPAN_DISTRIBUTION := PAX-$(DIST_VERSION)
CPAN_TARBALL := $(CPAN_DISTRIBUTION).tar.gz

.PHONY: test capture inspect hir compile build diff bench bench-matrix run-native corpus core-suite cpan-matrix dispatch profile run why-not trace-guards gatekeeper docker-build docker-test docker-shell docker-inspect docker-compile docker-run-native docker-corpus docker-core-suite docker-cpan-matrix docker-dispatch docker-profile docker-bench-matrix docker-run docker-why-not docker-trace-guards docker-gatekeeper cpan-clean cpan-dist cpan-build cpan-release cpan-sync-versions cpan-bump-version cpan-verify-paths cpan-gate git-gate

test:
	prove -lr t

capture:
	$(PERL) bin/pax capture t/fixtures/simple.pl

inspect:
	$(PERL) bin/pax inspect t/fixtures/simple.pl

hir:
	$(PERL) bin/pax hir t/fixtures/simple.pl

compile:
	$(PERL) bin/pax compile t/fixtures/simple.pl

build:
	$(PERL) bin/pax build --paxfile t/fixtures/paxfile.yml

diff:
	$(PERL) bin/pax diff t/fixtures/simple.pl

bench:
	$(PERL) bin/pax bench --iterations 1 t/fixtures/simple.pl

bench-matrix:
	$(PERL) bin/pax bench-matrix --iterations 1 t/benchmark_matrix.json

run-native:
	$(PERL) bin/pax run-native --left 10 --right 32 t/fixtures/simple.pl

corpus:
	$(PERL) bin/pax corpus t/corpus.json

core-suite:
	$(PERL) bin/pax core-suite t/perl_core_suite.json

cpan-matrix:
	$(PERL) bin/pax cpan-matrix t/cpan_matrix.json

dispatch:
	$(PERL) bin/pax dispatch --left 10 --right 32 t/fixtures/simple.pl

profile:
	$(PERL) bin/pax profile --iterations 2 --threshold 2 --region add t/fixtures/native_leafs.pl

run:
	$(PERL) bin/pax run --paxfile t/fixtures/paxfile.yml -- status

why-not:
	$(PERL) bin/pax why-not --region add t/fixtures/native_leafs.pl

trace-guards:
	$(PERL) bin/pax trace-guards --region add t/fixtures/native_leafs.pl

gatekeeper:
	$(PERL) bin/pax gatekeeper

cpan-clean:
	rm -rf .build $(CPAN_DISTRIBUTION) $(CPAN_TARBALL) .dzil

cpan-dist:
	command -v dzil >/dev/null 2>&1 || (echo "Dist::Zilla is required: cpanm Dist::Zilla" && exit 1)
	$(MAKE) cpan-clean
	dzil build
	@tmp_dir=$$(mktemp -d); \
	tar -xzf "$(CPAN_TARBALL)" -C "$$tmp_dir"; \
	rm -rf "$$tmp_dir/$(CPAN_DISTRIBUTION)/t/tmp"*; \
	tar -czf "$(CPAN_TARBALL)" -C "$$tmp_dir" "$(CPAN_DISTRIBUTION)"; \
	rm -rf "$$tmp_dir"

cpan-build: cpan-dist
	@echo "PAX distribution $(CPAN_TARBALL) built"

cpan-gate: cpan-dist cpan-verify-paths git-gate
	@echo "cpan-gate: CPAN and git gates OK"

cpan-verify-paths:
	@if [ ! -f "$(CPAN_TARBALL)" ]; then \
		echo "missing tarball $(CPAN_TARBALL)"; \
		exit 1; \
	fi
		@bad=$$(tar -tf "$(CPAN_TARBALL)" | \
		awk -v ver="$(DIST_VERSION)" '\
		BEGIN { \
			root = "PAX-" ver "/"; \
				n = split("DD Source Code/,projects/,project/,cover_db/,support/,pax-webapp/,blogs/,AGENTS.override.md,t/tmp", forbidden, ","); \
		} \
		{ \
			line = $$0; \
			base = line; gsub(/^.*\//, "", base); \
			ok = 0; \
			for (i = 1; i <= n; i++) { \
				if (index(line, root forbidden[i]) == 1) { ok = 1; break; } \
			} \
			if (!ok && substr(base, 1, 17) == "pax-runtime-probe-" && substr(base, length(base) - 2) == ".pl") { ok = 1; } \
				if (!ok && (line == root "SOW" || index(line, root "SOW") == 1 || index(line, "/SOW") > 0)) { ok = 1; } \
				if (!ok && index(line, "/.pax/") > 0) { ok = 1; } \
				if (!ok && index(line, root "t/tmp") == 1) { ok = 1; } \
				if (ok) { print line; } \
		}' ); \
	if [ -n "$$bad" ]; then \
		echo "blocked entries in $(CPAN_TARBALL):"; \
		echo "$$bad"; \
		exit 1; \
	fi
	@echo "cpan-gate: tarball path filters OK"

git-gate:
		@if [ -n "$$(git ls-files | grep -E '^(AGENTS[.]override[.]md|DD Source Code/|projects?/|project/|cover_db/|support/|pax-webapp/|blogs/|(^|/)t/tmp[^/]*(/|$$)|(^|/)pax-runtime-probe-[^/]+[.]pl$$|(^|/)SOW[^/]*($$|/))' )" ]; then \
			echo "git-gate: forbidden tracked files found in repository index"; \
			git ls-files | grep -E '^(AGENTS[.]override[.]md|DD Source Code/|projects?/|project/|cover_db/|support/|pax-webapp/|blogs/|(^|/)t/tmp[^/]*(/|$$)|(^|/)pax-runtime-probe-[^/]+[.]pl$$|(^|/)SOW[^/]*($$|/))'; \
			exit 1; \
	fi
	@echo "git-gate: forbidden tracked files are not staged in git"

cpan-release:
	command -v dzil >/dev/null 2>&1 || (echo "Dist::Zilla is required: cpanm Dist::Zilla" && exit 1)
	$(MAKE) cpan-dist
	dzil release

cpan-sync-versions:
	$(PERL) support/sync_versions.pl

cpan-bump-version:
	@if [ -z "$(VERSION)" ]; then echo "Usage: make cpan-bump-version VERSION=0.002"; exit 1; fi
	$(PERL) support/bump_version.pl $(VERSION)

.PHONY: docker-build docker-test docker-shell docker-inspect docker-compile

docker-build:
	$(DOCKER) build -t $(PAX_IMAGE) .

docker-test:
	$(DOCKER) run --rm -v $(CURDIR):/workspace -w /workspace $(PAX_IMAGE) make test

docker-shell:
	$(DOCKER) run --rm -it -v $(CURDIR):/workspace -w /workspace $(PAX_IMAGE) bash

docker-inspect:
	$(DOCKER) run --rm -v $(CURDIR):/workspace -w /workspace $(PAX_IMAGE) perl bin/pax inspect t/fixtures/simple.pl

docker-compile:
	$(DOCKER) run --rm -v $(CURDIR):/workspace -w /workspace $(PAX_IMAGE) perl bin/pax compile t/fixtures/simple.pl

docker-run-native:
	$(DOCKER) run --rm -v $(CURDIR):/workspace -w /workspace $(PAX_IMAGE) perl bin/pax run-native --left 10 --right 32 t/fixtures/simple.pl

docker-corpus:
	$(DOCKER) run --rm -v $(CURDIR):/workspace -w /workspace $(PAX_IMAGE) perl bin/pax corpus t/corpus.json

docker-core-suite:
	$(DOCKER) run --rm -v $(CURDIR):/workspace -w /workspace $(PAX_IMAGE) perl bin/pax core-suite t/perl_core_suite.json

docker-cpan-matrix:
	$(DOCKER) run --rm -v $(CURDIR):/workspace -w /workspace $(PAX_IMAGE) perl bin/pax cpan-matrix t/cpan_matrix.json

docker-dispatch:
	$(DOCKER) run --rm -v $(CURDIR):/workspace -w /workspace $(PAX_IMAGE) perl bin/pax dispatch --left 10 --right 32 t/fixtures/simple.pl

docker-profile:
	$(DOCKER) run --rm -v $(CURDIR):/workspace -w /workspace $(PAX_IMAGE) perl bin/pax profile --iterations 2 --threshold 2 --region add t/fixtures/native_leafs.pl

docker-bench-matrix:
	$(DOCKER) run --rm -v $(CURDIR):/workspace -w /workspace $(PAX_IMAGE) perl bin/pax bench-matrix --iterations 1 t/benchmark_matrix.json

docker-run:
	$(DOCKER) run --rm -v $(CURDIR):/workspace -w /workspace $(PAX_IMAGE) perl bin/pax run --left 10 --right 32 t/fixtures/simple.pl

docker-why-not:
	$(DOCKER) run --rm -v $(CURDIR):/workspace -w /workspace $(PAX_IMAGE) perl bin/pax why-not --region add t/fixtures/native_leafs.pl

docker-trace-guards:
	$(DOCKER) run --rm -v $(CURDIR):/workspace -w /workspace $(PAX_IMAGE) perl bin/pax trace-guards --region add t/fixtures/native_leafs.pl

docker-gatekeeper:
	$(DOCKER) run --rm -v $(CURDIR):/workspace -w /workspace $(PAX_IMAGE) perl bin/pax gatekeeper
