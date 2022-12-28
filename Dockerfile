# Strategy to choose between different versions of the application.
ARG SOURCE=eu

# This is the application as released by the European Commission.
FROM bitnami/minideb:bullseye AS assets-eu

ENV TL_NEU_VERSION          5.0
ENV TL_NEU_DOWNLOAD_URL     https://ec.europa.eu/digital-building-blocks/artifact/repository/esignaturetlm/eu/europa/ec/cef/esignature/TL-NEU/$TL_NEU_VERSION/TL-NEU-$TL_NEU_VERSION.zip

# This is a fork of the application with internationalization support.
FROM bitnami/minideb:bullseye AS assets-i18n

ENV TL_NEU_I18N_VERSION     0.1
ENV TL_NEU_DOWNLOAD_URL     https://github.com/zambonin/tlmanager/releases/download/$TL_NEU_I18N_VERSION/tlm-neu-5.0-i18n.zip

# This build stage downloads the application from one of the sources and unzips
# its contents to a known folder. It's a separate stage because files need to
# go into multiple containers. Caching this stage also helps because the
# download speed may not be very fast.
FROM assets-${SOURCE} AS assets

WORKDIR /root/tlm-neu-static

RUN install_packages \
    ca-certificates curl libarchive-tools

RUN curl -L $TL_NEU_DOWNLOAD_URL -o - \
    | bsdtar xf - --strip-components=1 -C /root/tlm-neu-static

# This stage sets up a Tomcat instance according to Sections 2.4 and 2.5 of
# the manual. The CAS server provided by the developers is used.
FROM tomcat:8.5.82-jre8-openjdk-slim-buster AS tomcat

ARG MYSQL_USER
ARG MYSQL_PASSWORD
ARG DOMAIN_NAME

COPY --from=assets /root/tlm-neu-static/webapps /usr/local/tomcat/webapps/
COPY --from=assets /root/tlm-neu-static/lib /usr/local/tomcat/lib/
COPY --from=assets \
    /root/tlm-neu-static/tlmanager-non-eu-config \
    /usr/local/tomcat/tlmanager-non-eu-config

# Section 2.5 of the manual points out that the persistence configuration is
# `create` for the first run and `validate` for all subsequent runs. Thus, the
# command below should be uncommented after the first run of the containers.
# RUN sed -i 's/create/validate/' \
#    /usr/local/tomcat/lib/application-tlmanager-non-eu-custom.properties

RUN sed -i "s/<USERNAME>/$MYSQL_USER/; \
            s/<PASSWORD>/$MYSQL_PASSWORD/; \
            s/localhost/mysql-tlm-neu/; \
            s|http://xxx.xxx.xxx.xxx:8080|$DOMAIN_NAME|" \
    /usr/local/tomcat/lib/application-tlmanager-non-eu-custom.properties

# This stage sets up a MySQL instance according to Section 2.3 of the manual.
FROM mysql:5.7.39-debian AS mysql

COPY --from=assets \
    /root/tlm-neu-static/migration-script.sql \
    /docker-entrypoint-initdb.d/

# This stage sets up a Caddy instance that simply rewrites and proxies URLs so
# that one can access the service directly via $DOMAIN_NAME.
FROM caddy:2.5.2-alpine AS caddy

ARG DOMAIN_NAME

RUN printf "$DOMAIN_NAME {\n\
	reverse_proxy tomcat-tlm-neu:8080\n\
	rewrite / /tl-manager-non-eu\n\
}\n" > /etc/caddy/Caddyfile
