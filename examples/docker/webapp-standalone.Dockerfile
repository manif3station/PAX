FROM perl:5.42.0 AS pax-build

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install -y --no-install-recommends build-essential ca-certificates cpanminus \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /pax
COPY . /pax
RUN if [ -f cpanfile ]; then cpanm --notest --installdeps .; fi
RUN perl bin/pax build --compact --no-paxfile -o /out/pax bin/pax

FROM perl:5.42.0 AS web-build

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install -y --no-install-recommends build-essential ca-certificates cpanminus \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /webapp
COPY examples/webapp /webapp
COPY --from=pax-build /out/pax /usr/local/bin/pax
RUN cpanm --notest Dancer2 Plack Starman Template
RUN cd /webapp && pax build --compact --paxfile paxfile.yml --output /out/pax-webapp

FROM debian:trixie-slim

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates libgcc-s1 \
    && rm -rf /var/lib/apt/lists/*

COPY --from=web-build /out/pax-webapp /usr/local/bin/pax-webapp
EXPOSE 5000
ENTRYPOINT ["/usr/local/bin/pax-webapp"]
CMD ["serve", "--host", "0.0.0.0", "--port", "5000"]
