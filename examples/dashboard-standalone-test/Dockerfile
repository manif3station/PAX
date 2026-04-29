FROM perl:5.42.0 AS pax-build

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install -y --no-install-recommends build-essential ca-certificates cpanminus \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /pax
COPY . /pax
RUN cpanm --notest --installdeps .
RUN perl bin/pax build -o /root/pax.bin bin/pax

FROM perl:5.42.0 AS dashboard-build

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install -y --no-install-recommends build-essential ca-certificates cpanminus \
    && rm -rf /var/lib/apt/lists/*

COPY --from=pax-build /root/pax.bin /usr/local/bin/pax
RUN chmod +x /usr/local/bin/pax
RUN cpanm --notest Developer::Dashboard
RUN mkdir -p /out
RUN perl -MTime::HiRes=time -e '$s=time; system q{dashboard}, q{version}; printf qq(real %.6f\n), time-$s; exit($? >> 8)' > /out/stock-dashboard-version.txt 2>&1
RUN pax build -o /root/d2 "$(command -v dashboard)"

FROM debian:trixie-slim

ENV DEBIAN_FRONTEND=noninteractive
ENV HOME=/root
ENV PATH=/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
ENV DEVELOPER_DASHBOARD_PROGRESS=1

RUN apt-get update \
    && apt-get install -y --no-install-recommends bash ca-certificates git libgcc-s1 procps \
    && rm -rf /var/lib/apt/lists/*

COPY --from=dashboard-build /root/d2 /usr/local/bin/d2
COPY --from=dashboard-build /out/stock-dashboard-version.txt /opt/bench/stock-dashboard-version.txt

CMD ["bash", "-lc", "set -eu; TIMEFORMAT='real %R'; mkdir -p /tmp/example-skill/cli /tmp/example-skill/config /tmp/example-skill/state /tmp/example-skill/logs; cat > /tmp/example-skill/cli/run-test <<'EOF'\n#!/usr/bin/env perl\nuse strict;\nuse warnings;\nprint qq(skill-ok\\n);\nEOF\nchmod +x /tmp/example-skill/cli/run-test; printf '{\"skill_name\":\"example-skill\"}\\n' > /tmp/example-skill/config/config.json; printf 'VERSION=0.01\\n' > /tmp/example-skill/.env; git -C /tmp/example-skill init --quiet; git -C /tmp/example-skill config user.email test@example.com; git -C /tmp/example-skill config user.name Test; git -C /tmp/example-skill add .; git -C /tmp/example-skill commit -m init --quiet; echo 'stock dashboard version'; cat /opt/bench/stock-dashboard-version.txt; echo 'standalone d2 version (cold)'; time /usr/local/bin/d2 version; echo 'standalone d2 version (warm cache)'; time /usr/local/bin/d2 version; d2 init; d2 restart; d2 shell bash; d2 ps1; printf '{\"alpha\":{\"beta\":2}}\\n' | d2 jq .alpha.beta; mkdir -p /tmp/ofdemo; printf 'demo\\n' > /tmp/ofdemo/example.txt; d2 of --print /tmp/ofdemo example.txt; find /root/.developer-dashboard/cli/dd -maxdepth 1 -type f -printf '%f\\n' | while IFS= read -r helper; do [ -n \"$helper\" ] || continue; output=\"$(timeout 10 /usr/local/bin/d2 --pax-standalone-helper \"$helper\" --help 2>&1 || true)\"; if printf '%s' \"$output\" | grep -q \"Unsupported built-in dashboard command\"; then printf 'helper routing failed for %s\\n' \"$helper\" >&2; exit 1; fi; done; d2 skills install /tmp/example-skill; d2 example-skill.run-test"]
