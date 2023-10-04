# syntax=docker/dockerfile:1-labs
FROM public.ecr.aws/docker/library/alpine:3.18 AS base
ENV TZ=UTC

# source stage =================================================================
FROM base AS source

WORKDIR /src
ARG BRANCH
ARG VERSION

# mandatory build-arg
RUN test -n "$BRANCH" && test -n "$VERSION"

# get and extract source from git
ADD https://github.com/sabnzbd/sabnzbd.git#$VERSION ./

# dependencies
# RUN apk add --no-cache patch

# apply available patches
# COPY patches ./
# RUN find . -name "*.patch" -print0 | sort -z | xargs -t -0 -n1 patch -p1 -i

# unrar stage ==================================================================
FROM base as build-unrar

WORKDIR /src
ARG UNRAR_VERSION=6.2.8

# get and extract
RUN wget -qO- https://www.rarlab.com/rar/unrarsrc-$UNRAR_VERSION.tar.gz | tar xz --strip-component 1

# dependencies
RUN apk add --no-cache build-base

# build
RUN make && \
    make install

# par2cmdline-turbo stage  =====================================================
FROM base as build-par2

WORKDIR /src
ARG PAR2_VERSION=1.0.1

# get and extract source from git
ADD https://github.com/animetosho/par2cmdline-turbo.git#v$PAR2_VERSION ./

# dependencies
RUN apk add --no-cache build-base automake autoconf

# build
RUN ./automake.sh && \
    ./configure --prefix=/usr && \
    make && \
    make install

# backend stage ================================================================
FROM base AS build-backend

# dependencies
RUN apk add --no-cache build-base python3-dev libffi-dev

# copy requirements
COPY --from=source /src/requirements.txt ./

# creates python env
RUN python3 -m venv /opt/venv && \
    /opt/venv/bin/pip install -r requirements.txt

# runtime stage ================================================================
FROM base

ENV S6_VERBOSITY=0 S6_BEHAVIOUR_IF_STAGE2_FAILS=2 PUID=65534 PGID=65534
WORKDIR /config
VOLUME /config
EXPOSE 8080

# copy files
COPY --from=build-unrar /usr/bin/unrar /usr/bin/unrar
COPY --from=build-par2 /usr/bin/par2 /usr/bin/par2
COPY --from=build-backend /opt/venv /opt/venv
COPY --from=source /src /app
COPY ./rootfs /

# runtime dependencies
RUN apk add --no-cache tzdata s6-overlay libgomp python3 7zip curl

# creates python env
ENV PATH="/opt/venv/bin:$PATH"

# run using s6-overlay
ENTRYPOINT ["/init"]
