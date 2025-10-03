# syntax=docker/dockerfile:1

#
# Stage 1: Build a tiny rootfs with curl and jq on UBI 9
#
FROM registry.access.redhat.com/ubi9 AS ubi-tools
RUN mkdir -p /mnt/rootfs \
 && dnf -y --installroot /mnt/rootfs --releasever 9 \
      --setopt=install_weak_deps=false --nodocs \
      install curl jq \
 && dnf --installroot /mnt/rootfs clean all \
 && rm -rf /mnt/rootfs/var/cache/dnf/*

#
# Stage 2: Final Keycloak image
#
FROM quay.io/keycloak/keycloak:26.4

# Copy curl and jq binaries from UBI9 with all dependencies
USER root
COPY --from=ubi-tools /mnt/rootfs/usr/bin/curl /usr/bin/curl
COPY --from=ubi-tools /mnt/rootfs/usr/bin/jq /usr/bin/jq
# Copy all required libraries for curl and jq
COPY --from=ubi-tools /mnt/rootfs/usr/lib64/ /usr/lib64/

# Copy scripts
COPY create-users.sh /opt/keycloak/create-users.sh
COPY entrypoint-wrapper.sh /opt/keycloak/entrypoint-wrapper.sh
RUN chmod +x /opt/keycloak/create-users.sh /opt/keycloak/entrypoint-wrapper.sh && \
    chown keycloak:keycloak /opt/keycloak/create-users.sh /opt/keycloak/entrypoint-wrapper.sh

USER keycloak

ENV KC_HEALTH_ENABLED=true
ENV KC_DB=postgres

# Build Keycloak with database configuration
RUN /opt/keycloak/bin/kc.sh build --db=postgres

ENTRYPOINT ["/opt/keycloak/entrypoint-wrapper.sh"]
CMD ["start", "--import-realm", "--http-enabled=true", "--hostname-strict=false", "--proxy-headers=xforwarded", "--optimized"]
