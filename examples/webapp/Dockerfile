FROM perl:5.42.0 AS build

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        build-essential \
        cpanminus \
        ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /workspace/examples/webapp
COPY bin /workspace/bin
COPY lib /workspace/lib
COPY examples/webapp /workspace/examples/webapp

RUN cpanm --notest Dancer2 Plack Starman Template

RUN perl -I/workspace/lib /workspace/bin/pax build --compact --paxfile paxfile.yml > /tmp/pax-webapp-build.json

FROM debian:trixie-slim

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        libgcc-s1 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY --from=build /workspace/examples/webapp/.pax/standalone/pax-webapp/pax-webapp /app/pax-webapp

EXPOSE 5000

ENTRYPOINT ["/app/pax-webapp"]
CMD ["serve", "--host", "0.0.0.0", "--port", "5000"]
