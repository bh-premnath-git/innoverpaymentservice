# syntax=docker/dockerfile:1

FROM quay.io/keycloak/keycloak:26.4

USER root
RUN microdnf install -y curl \
    && microdnf clean all

USER 1000

ENV KC_HEALTH_ENABLED=true

ENTRYPOINT ["/opt/keycloak/bin/kc.sh"]

CMD ["start"]
