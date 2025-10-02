# syntax=docker/dockerfile:1

FROM quay.io/keycloak/keycloak:latest AS builder

FROM eclipse-temurin:21-jre-jammy

RUN apt-get update \
    && apt-get install -y --no-install-recommends curl \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /opt/keycloak /opt/keycloak

RUN groupadd -r keycloak \
    && useradd -r -g keycloak -d /opt/keycloak -s /bin/sh keycloak \
    && chown -R keycloak:keycloak /opt/keycloak

USER keycloak

WORKDIR /opt/keycloak

ENV KC_HEALTH_ENABLED=true

ENTRYPOINT ["/opt/keycloak/bin/kc.sh"]

CMD ["start"]
