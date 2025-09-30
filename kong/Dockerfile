FROM kong:latest

USER root

RUN set -eux; \
    apt-get update; \
    apt-get install -y curl; \
    rm -rf /var/lib/apt/lists/*

RUN set -eux; \
    luarocks install lua-resty-openidc 1.7.5-1; \
    luarocks install lua-resty-session 3.11-1

RUN set -eux; \
    mkdir -p /usr/local/share/lua/5.1/kong/plugins/openid-connect

COPY vendor/openid-connect /usr/local/share/lua/5.1/kong/plugins/openid-connect

RUN chown -R kong:kong /usr/local/share/lua/5.1/kong/plugins/openid-connect

USER kong
