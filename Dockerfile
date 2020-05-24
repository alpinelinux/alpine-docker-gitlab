FROM ruby:2.6-alpine

ENV GITLAB_VERSION=12.10.6
ENV PROTOBUF_VERSION=3.12.1

COPY overlay /

RUN  setup.sh

EXPOSE 22 80

ENTRYPOINT [ "entrypoint.sh" ]

CMD [ "start" ]
