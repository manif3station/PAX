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
    && apt-get install -y --no-install-recommends bash ca-certificates libgcc-s1 procps \
    && rm -rf /var/lib/apt/lists/*

COPY --from=dashboard-build /root/d2 /usr/local/bin/d2
COPY --from=dashboard-build /out/stock-dashboard-version.txt /opt/bench/stock-dashboard-version.txt

CMD ["bash", "-lc", "set -eu; TIMEFORMAT='real %R'; echo 'stock dashboard version'; cat /opt/bench/stock-dashboard-version.txt; echo 'standalone d2 version (cold)'; time /usr/local/bin/d2 version; echo 'standalone d2 version (warm cache)'; time /usr/local/bin/d2 version; d2 init; d2 restart; d2 shell bash -lc 'exit 0'"]
