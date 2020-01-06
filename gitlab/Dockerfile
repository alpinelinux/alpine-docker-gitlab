FROM ruby:2.6-alpine

ENV GITLAB_VERSION=12.4.7
ARG GRPC_VERSION=1.19.0

COPY gitlab/overlay/ /

RUN  setup.sh

EXPOSE 22 80

ENTRYPOINT [ "entrypoint.sh" ]

CMD [ "start" ]
