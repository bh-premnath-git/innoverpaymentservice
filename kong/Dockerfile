FROM kong:latest

USER root

RUN set -eux; \
    mkdir -p /usr/local/share/lua/5.1/kong/plugins/openid-connect

COPY vendor/openid-connect /usr/local/share/lua/5.1/kong/plugins/openid-connect

RUN chown -R kong:kong /usr/local/share/lua/5.1/kong/plugins/openid-connect

USER kong
