version: 0.1
storage:
{%- if getenv "GL_REGISTRY_S3_BUCKET" "" %}
  s3_v2:
    accesskey: {% .Env.GL_REGISTRY_S3_ACCESSKEY %}
    secretkey: {% .Env.GL_REGISTRY_S3_SECRET %}
    region: {% .Env.GL_REGISTRY_S3_REGION %}
    regionendpoint: {% .Env.GL_REGISTRY_S3_ENDPOINT %}
    bucket: {% .Env.GL_REGISTRY_S3_BUCKET %}
    secure: true
    v4auth: true
    rootdirectory: /
    # fix compattibility issue with linode object storage
    # see: https://www.linode.com/community/questions/24117
    multipartcopythresholdsize: 5368709120
{% end %}
  delete:
    enabled: true
  maintenance:
    readonly:
      enabled: {% getenv "GL_REGISTRY_MAINTENANCE_READONLY" "false" %}
redis:
  addr: redis:6379
  db: 1
http:
  addr: 0.0.0.0:5000
  secret: notused
auth:
  token:
    realm: {% .Env.GL_REGISTRY_TOKEN_REALM %}
    service: container_registry
    issuer: gitlab-issuer
    rootcertbundle: /etc/docker/certs/gitlab.crt
    autoredirect: false
{%- if getenv "GL_REGISTRY_DB" "" %}
database:
  enabled: {% getenv "GL_REGISTRY_DB_ENABLED" "true" %}
  host: {% .Env.GL_REGISTRY_DB_HOST %}
  user: {% .Env.GL_REGISTRY_DB_USER %}
  password: {% .Env.GL_REGISTRY_DB_PASSWORD %}
  dbname: {% .Env.GL_REGISTRY_DB %}
  sslmode: disable
{% end %}
