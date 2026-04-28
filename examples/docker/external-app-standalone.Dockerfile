ARG PAX_CONTEXT=.
ARG APP_CONTEXT=.

FROM perl:5.42.0 AS pax-build

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install -y --no-install-recommends build-essential ca-certificates cpanminus \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /pax
ARG PAX_CONTEXT
COPY ${PAX_CONTEXT} /pax
RUN cpanm --notest --installdeps .
RUN perl bin/pax build -o /out/pax bin/pax

FROM perl:5.42.0 AS app-build

ENV DEBIAN_FRONTEND=noninteractive

ARG APP_ENTRYPOINT=bin/dashboard
ARG APP_OUTPUT=/out/app
ARG APP_CONTEXT="."

RUN apt-get update \
    && apt-get install -y --no-install-recommends build-essential ca-certificates cpanminus \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
RUN rm -rf /app/*
COPY ${APP_CONTEXT} /app
COPY --from=pax-build /out/pax /usr/local/bin/pax
RUN if [ -f cpanfile ]; then cpanm --notest --installdeps .; fi
RUN if [ -f paxfile.yml ]; then pax build --paxfile paxfile.yml -o ${APP_OUTPUT} ${APP_ENTRYPOINT}; else pax build -o ${APP_OUTPUT} ${APP_ENTRYPOINT}; fi

FROM debian:trixie-slim

ENV DEBIAN_FRONTEND=noninteractive

ARG APP_OUTPUT=/out/app

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates libgcc-s1 \
    && rm -rf /var/lib/apt/lists/*

COPY --from=app-build ${APP_OUTPUT} /usr/local/bin/app
ENTRYPOINT ["/usr/local/bin/app"]
