PERL ?= perl
DOCKER ?= docker
PAX_IMAGE ?= pax-dev:perl-5.42

.PHONY: test build run docker-build docker-test docker-shell docker-build-app docker-run cpan-clean cpan-reset cpan-dist cpan-build cpan-release cpan-sync-versions cpan-bump-version cpan-auto-bump version-gate doc-gate changes-gate release-gate cpan-verify-paths cpan-gate git-gate

test:
	prove -lr t

build:
	$(PERL) bin/pax build --paxfile t/fixtures/paxfile.yml

run:
	$(PERL) bin/pax run --paxfile t/fixtures/paxfile.yml -- status

cpan-clean:
	rm -rf .build .dzil
	@find . -maxdepth 1 -type d -name 'PAX-*' -exec rm -rf {} +

cpan-reset:
	rm -rf .build .dzil
	@find . -maxdepth 1 \( -type d -o -type f \) \( -name 'PAX-*' -o -name 'PAX-*.tar.gz' -o -name 'PAX-*.tgz' \) -exec rm -rf {} +

version-gate:
	$(PERL) tools/version_gate.pl

doc-gate:
	$(PERL) tools/doc_gate.pl

changes-gate:
	$(PERL) tools/changes_gate.pl

release-gate: version-gate changes-gate doc-gate
	@echo "release-gate: version, Changes, and docs OK"

cpan-auto-bump:
	@next="$$( $(PERL) tools/next_version.pl )"; \
	echo "cpan-auto-bump: bumping version to $$next"; \
	$(PERL) tools/bump_version.pl "$$next"

cpan-dist: release-gate
	command -v dzil >/dev/null 2>&1 || (echo "Dist::Zilla is required: cpanm Dist::Zilla" && exit 1)
	$(MAKE) cpan-reset
	dzil build
	@version="$$( $(PERL) -Ilib -MPAX -e 'print $$PAX::VERSION' )"; \
	dist="PAX-$$version"; \
	tarball="$$dist.tar.gz"; \
	tmp_dir="$$(mktemp -d)"; \
	tar -xzf "$$tarball" -C "$$tmp_dir"; \
	rm -rf "$$tmp_dir/$$dist/t/tmp"*; \
	tar -czf "$$tarball" -C "$$tmp_dir" "$$dist"; \
	rm -rf "$$tmp_dir"

cpan-build: cpan-dist
	@version="$$( $(PERL) -Ilib -MPAX -e 'print $$PAX::VERSION' )"; \
	echo "PAX distribution PAX-$$version.tar.gz built"

cpan-gate: cpan-dist cpan-verify-paths git-gate
	@echo "cpan-gate: CPAN and git gates OK"

cpan-verify-paths:
	@version="$$( $(PERL) -Ilib -MPAX -e 'print $$PAX::VERSION' )"; \
	tarball="PAX-$$version.tar.gz"; \
	if [ ! -f "$$tarball" ]; then \
		echo "missing tarball $$tarball"; \
		exit 1; \
	fi; \
	bad=$$(tar -tf "$$tarball" | \
		awk -v ver="$$version" '\
		BEGIN { \
			root = "PAX-" ver "/"; \
				n = split("DD Source Code/,projects/,project/,cover_db/,support/,pax-webapp/,blogs/,examples/,tools/,docs/,AGENTS.override.md,t/tmp", forbidden, ","); \
		} \
		{ \
			line = $$0; \
			base = line; gsub(/^.*\//, "", base); \
			ok = 0; \
			for (i = 1; i <= n; i++) { \
				if (index(line, root forbidden[i]) == 1) { ok = 1; break; } \
			} \
			if (!ok && substr(base, 1, 17) == "pax-runtime-probe-" && substr(base, length(base) - 2) == ".pl") { ok = 1; } \
			if (!ok && (base == "BACKLOG.md" || base == "Dockerfile" || base == "DOCKER.md" || base == "docker-compose.yml")) { ok = 1; } \
				if (!ok && (line == root "SOW" || index(line, root "SOW") == 1 || index(line, "/SOW") > 0)) { ok = 1; } \
				if (!ok && index(line, "/.pax/") > 0) { ok = 1; } \
				if (!ok && index(line, root "t/tmp") == 1) { ok = 1; } \
				if (ok) { print line; } \
		}' ); \
	if [ -n "$$bad" ]; then \
		echo "blocked entries in $$tarball:"; \
		echo "$$bad"; \
		exit 1; \
	fi
	@echo "cpan-gate: tarball path filters OK"

git-gate:
	@forbidden="$$(git ls-files | grep -E '^(AGENTS[.]override[.]md|DD Source Code/|projects?/|project/|cover_db/|support/|pax-webapp/|blogs/|(^|/)t/tmp[^/]*(/|$$)|(^|/)pax-runtime-probe-[^/]+[.]pl$$|(^|/)SOW[^/]*($$|/))' || true)"; \
		if [ -n "$$forbidden" ]; then \
			echo "git-gate: forbidden tracked files found in repository index"; \
			echo "$$forbidden"; \
			exit 1; \
	fi
	@dirty="$$(git status --short)"; \
		if [ -n "$$dirty" ]; then \
			echo "git-gate: working tree is not clean"; \
			echo "$$dirty"; \
			exit 1; \
		fi
	@echo "git-gate: forbidden tracked files absent and working tree clean"

cpan-release:
	command -v cpan-upload >/dev/null 2>&1 || (echo "CPAN::Uploader is required: cpanm CPAN::Uploader" && exit 1)
	$(MAKE) cpan-gate
	@version="$$( $(PERL) -Ilib -MPAX -e 'print $$PAX::VERSION' )"; \
	tarball="PAX-$$version.tar.gz"; \
	if [ ! -f "$$tarball" ]; then \
		echo "missing tarball $$tarball"; \
		exit 1; \
	fi; \
	cpan-upload "$$tarball"

cpan-sync-versions:
	$(PERL) tools/sync_versions.pl

cpan-bump-version:
	@if [ -z "$(VERSION)" ]; then echo "Usage: make cpan-bump-version VERSION=0.002"; exit 1; fi
	$(PERL) tools/bump_version.pl $(VERSION)

docker-build:
	$(DOCKER) build -t $(PAX_IMAGE) .

docker-test:
	$(DOCKER) run --rm -v $(CURDIR):/workspace -w /workspace $(PAX_IMAGE) make test

docker-shell:
	$(DOCKER) run --rm -it -v $(CURDIR):/workspace -w /workspace $(PAX_IMAGE) bash

docker-build-app:
	$(DOCKER) run --rm -v $(CURDIR):/workspace -w /workspace $(PAX_IMAGE) perl bin/pax build --paxfile t/fixtures/paxfile.yml

docker-run:
	$(DOCKER) run --rm -v $(CURDIR):/workspace -w /workspace $(PAX_IMAGE) perl bin/pax run --paxfile t/fixtures/paxfile.yml -- status
