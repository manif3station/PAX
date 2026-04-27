FROM perl:5.42.0 AS build

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install -y --no-install-recommends build-essential ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /pax
COPY . /pax
RUN perl bin/pax build --compact --no-paxfile -o /out/pax bin/pax

FROM debian:trixie-slim

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates libgcc-s1 \
    && rm -rf /var/lib/apt/lists/*

COPY --from=build /out/pax /usr/local/bin/pax
ENTRYPOINT ["/usr/local/bin/pax"]
CMD ["help"]
