FROM curlimages/curl AS source

ARG GITALY_SERVER_VERSION

WORKDIR /tmp/src
USER root

COPY overlay /

RUN setup fetch_source
