FROM alpine:3.23 AS builder

WORKDIR /build

RUN apk add --no-cache \
    bash \
    bison \
    build-base \
    flex \
    linux-headers \
    perl

COPY . .

RUN ./configure \
    --prefix=/usr/local/pgsql \
    --without-readline \
    --without-zlib \
    --without-icu \
 && make -j"$(getconf _NPROCESSORS_ONLN)" \
 && make install


FROM alpine:3.23

ENV PGDATA=/var/lib/postgresql/data
ENV PATH=/usr/local/pgsql/bin:$PATH

RUN apk add --no-cache \
    libgcc \
    libstdc++ \
    su-exec \
 && addgroup -S postgres \
 && adduser -S -D -h /var/lib/postgresql -s /bin/sh -G postgres postgres \
 && mkdir -p /var/lib/postgresql/data /docker-entrypoint-initdb.d \
 && chown -R postgres:postgres /var/lib/postgresql /docker-entrypoint-initdb.d

COPY --from=builder /usr/local/pgsql /usr/local/pgsql
COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh

RUN chmod +x /usr/local/bin/docker-entrypoint.sh

VOLUME ["/var/lib/postgresql/data"]
EXPOSE 5432

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD ["postgres"]
