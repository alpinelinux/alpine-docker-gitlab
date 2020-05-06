FROM ruby:2.6-alpine

ENV GITLAB_VERSION=12.10.4
ARG GRPC_VERSION=1.24.3

COPY overlay /

RUN  setup.sh

EXPOSE 22 80

ENTRYPOINT [ "entrypoint.sh" ]

CMD [ "start" ]
