FROM bitnami/minideb:bullseye AS assets

ENV TL_NEU_VERSION          5.0
ENV TL_NEU_DOWNLOAD_URL     https://ec.europa.eu/digital-building-blocks/artifact/repository/esignaturetlm/eu/europa/ec/cef/esignature/TL-NEU/$TL_NEU_VERSION/TL-NEU-$TL_NEU_VERSION.zip

WORKDIR /root/tlm-neu-static

RUN install_packages \
    ca-certificates curl libarchive-tools

RUN curl $TL_NEU_DOWNLOAD_URL -o - \
    | bsdtar xf - --strip-components=1 -C /root/tlm-neu-static

FROM tomcat:8.5.82-jre8-openjdk-slim-buster AS tomcat

COPY --from=assets /root/tlm-neu-static/webapps /usr/local/tomcat/webapps/
COPY --from=assets /root/tlm-neu-static/lib /usr/local/tomcat/lib/
COPY --from=assets \
    /root/tlm-neu-static/tlmanager-non-eu-config \
    /usr/local/tomcat/tlmanager-non-eu-config

# Section 2.5 of the manual points out that the persistence configuration is
# `create` for the first run and `validate` for all subsequent runs. Thus, the
# command below should be uncommented after the first run of the containers.
#
RUN sed -i 's/create/validate/' \
   /usr/local/tomcat/lib/application-tlmanager-non-eu-custom.properties

# USERNAME and PASSWORD are MYSQL_USER and MYSQL_PASSWORD from the
# `docker-compose.yml` file, respectively. `localhost` is swapped by the name
# of the container.
RUN sed -i 's/<USERNAME>/user/; \
            s/<PASSWORD>/changeme/; \
            s/localhost/mysql-tlm-neu/; \
            s/xxx.xxx.xxx.xxx/localhost/' \
    /usr/local/tomcat/lib/application-tlmanager-non-eu-custom.properties

FROM mysql:5.7.39-debian AS mysql

COPY --from=assets \
    /root/tlm-neu-static/migration-script.sql \
    /docker-entrypoint-initdb.d/
