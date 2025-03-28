# syntax=docker/dockerfile:1-labs
FROM public.ecr.aws/docker/library/alpine:3.21 AS base
ENV TZ=UTC
WORKDIR /src

# source stage =================================================================
FROM base AS source

# get and extract source from git
ARG BRANCH
ARG VERSION
ADD https://github.com/sabnzbd/sabnzbd.git#${BRANCH:-$VERSION} ./

# unrar stage ==================================================================
FROM base AS build-unrar

# dependencies
RUN apk add --no-cache build-base linux-headers

# get and extract
ARG UNRAR_VERSION=6.2.8
RUN wget -qO- https://www.rarlab.com/rar/unrarsrc-$UNRAR_VERSION.tar.gz | tar xz --strip-component 1

# build
RUN make && make install

# par2cmdline-turbo stage  =====================================================
FROM base AS build-par2

# dependencies
RUN apk add --no-cache build-base automake autoconf

# get and extract source from git
ARG PAR2_VERSION=1.0.1
ADD https://github.com/animetosho/par2cmdline-turbo.git#v$PAR2_VERSION ./

# build
RUN ./automake.sh && ./configure --prefix=/usr && \
    make && make install-strip

# backend stage ================================================================
FROM base AS build-backend

# dependencies
RUN apk add --no-cache build-base python3-dev libffi-dev

# copy requirements
COPY --from=source /src/requirements.txt ./

# creates python env
RUN python3 -m venv /opt/venv && \
    /opt/venv/bin/pip install -r requirements.txt

# translations
COPY --from=source /src/po ./po
COPY --from=source /src/email ./email
COPY --from=source /src/tools/msgfmt.py /src/tools/make_mo.py ./
RUN /opt/venv/bin/python make_mo.py

# runtime stage ================================================================
FROM base

ENV S6_VERBOSITY=0 S6_BEHAVIOUR_IF_STAGE2_FAILS=2 PUID=65534 PGID=65534
WORKDIR /config
VOLUME /config
EXPOSE 8080

# copy files
COPY --from=source /src/sabnzbd /app/sabnzbd
COPY --from=source /src/interfaces /app/interfaces
COPY --from=source /src/SABnzbd.py /app/
COPY --from=build-unrar /usr/bin/unrar /usr/bin/
COPY --from=build-par2 /usr/bin/par2* /usr/bin/
COPY --from=build-backend /opt/venv /opt/venv
COPY --from=build-backend /src/email /app/email
COPY --from=build-backend /src/locale /app/locale
COPY ./rootfs/. /

# runtime dependencies
RUN apk add --no-cache tzdata s6-overlay libgomp python3 7zip curl

# creates python env
ENV PATH="/opt/venv/bin:$PATH"

# run using s6-overlay
ENTRYPOINT ["/init"]
