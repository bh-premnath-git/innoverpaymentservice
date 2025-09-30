FROM kong:latest

USER root

RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends git; \
    rm -rf /var/lib/apt/lists/*; \
    mkdir -p /tmp/kong-plugins && \
    git clone --depth=1 https://github.com/nokia/kong-plugins.git /tmp/kong-plugins && \
    mkdir -p /usr/local/share/lua/5.1/kong/plugins && \
    cp -r /tmp/kong-plugins/kong/plugins/openid-connect /usr/local/share/lua/5.1/kong/plugins/openid-connect && \
    rm -rf /tmp/kong-plugins && \
    chown -R kong:kong /usr/local/share/lua/5.1/kong/plugins/openid-connect

USER kong
