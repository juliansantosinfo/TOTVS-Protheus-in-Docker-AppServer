ARG IMAGE_BASE=redhat/ubi8:8.5-236
# hadolint ignore=DL3006
FROM ${IMAGE_BASE}

LABEL release="12.1.2410"
LABEL build="24.3.1.1"
LABEL dbapi="24.1.1.0"
LABEL webapp="10.1.4"
# Correção ortográfica: "Aplication" -> "Application"
LABEL description="TOTVS Application Server Protheus" 
LABEL maintainer="Julian de Almeida Santos <julian.santos.info@gmail.com>"

ARG COMPRESS_RESOURCES=true

# Invalida cache quando COMPRESS_RESOURCES muda
LABEL compress-resources="${COMPRESS_RESOURCES}"

ENV APPSERVER_MODE=application
ENV APPSERVER_RPO_CUSTOM="/totvs/protheus/apo/custom.rpo"
ENV APPSERVER_DBACCESS_DATABASE=MSSQL
ENV APPSERVER_DBACCESS_SERVER=totvs_dbaccess
ENV APPSERVER_DBACCESS_PORT=7890
ENV APPSERVER_DBACCESS_ALIAS=protheus
ENV APPSERVER_CONSOLEFILE="/totvs/protheus/bin/appserver/appserver.log"
ENV APPSERVER_MULTIPROTOCOLPORTSECURE=0
ENV APPSERVER_MULTIPROTOCOLPORT=1
ENV APPSERVER_LICENSE_SERVER=totvs_licenseserver
ENV APPSERVER_LICENSE_PORT=5555
ENV APPSERVER_PORT=1234
ENV APPSERVER_WEB_PORT=1235
ENV APPSERVER_REST_PORT=8080
ENV APPSERVER_ENVIRONMENT_LOCALFILES=SQLITE
ENV APPSERVER_SQLITE_SERVER=totvs_appsqlite
ENV APPSERVER_SQLITE_PORT=12346
ENV APPSERVER_SQLITE_INSTANCES="1,10,1,1"
ENV LICENSESERVER_CHECK=false
ENV LICENSE_WAIT_RETRIES=30
ENV LICENSE_WAIT_INTERVAL=2
ENV DBACCESS_CHECK=false
ENV DBACCESS_WAIT_RETRIES=30
ENV DBACCESS_WAIT_INTERVAL=2
ENV EXTRACT_RESOURCES=true
ENV DEBUG_SCRIPT=false
ENV TZ=America/Sao_Paulo

WORKDIR /

RUN PKG_MGR=$(command -v dnf || command -v microdnf) && \
    $PKG_MGR update -y && \
    $PKG_MGR install -y gzip iputils nano procps-ng dmidecode tar && \
    $PKG_MGR clean all && \
    rm -rf /var/cache/dnf

COPY ./entrypoint.sh ./healthcheck.sh ./service.sh /

RUN chmod +x /entrypoint.sh /healthcheck.sh /service.sh

COPY ./totvs /totvs

WORKDIR /totvs

RUN if [ "$COMPRESS_RESOURCES" = "true" ]; then \
    tar czvf protheus.tar.gz protheus && \
    tar czvf protheus_data.tar.gz protheus_data && \
    rm -rf protheus protheus_data; \
    fi

HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD (echo > /dev/tcp/localhost/1234) && (echo > /dev/tcp/localhost/1235) || exit 1

ENTRYPOINT [ "/entrypoint.sh" ]

EXPOSE 1234 1235 8080
