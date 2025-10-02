# syntax=docker/dockerfile:1
FROM registry.access.redhat.com/ubi9 AS curl-builder

RUN dnf install -y --setopt=install_weak_deps=False curl \
    && dnf clean all \
    && mkdir -p /curl-root/usr/bin \
    && cp /usr/bin/curl /curl-root/usr/bin/ \
    && ldd /usr/bin/curl | awk '{print $3}' | grep '^/' | xargs -I '{}' cp --parents '{}' /curl-root

FROM quay.io/keycloak/keycloak:26.4
USER root
COPY --from=curl-builder /curl-root/ /
USER 1000
ENV KC_HEALTH_ENABLED=true
ENTRYPOINT ["/opt/keycloak/bin/kc.sh"]
CMD ["start"]
