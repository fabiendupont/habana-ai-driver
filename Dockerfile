ARG ARCH="x86_64"
ARG RHEL_VERSION=""
ARG KERNEL_VERSION=""
ARG BASE_DIGEST=""

FROM ghcr.io/smgglrs/driver-toolkit:${KERNEL_VERSION}.${ARCH} as builder

ARG ARCH="x86_64"
ARG HABANA_VERSION=""
ARG HABANA_GIT_SHA=""
ARG KERNEL_VERSION=""
ARG RHEL_VERSION=""

RUN mkdir -p /home/builder/habanalabs \
    && cd /home/builder/habanalabs \
    && rpm2cpio https://vault.habana.ai/artifactory/rhel/8/${RHEL_VERSION}/habanalabs-${HABANA_VERSION}.el8.noarch.rpm | cpio -id \
    && rpm2cpio https://vault.habana.ai/artifactory/rhel/8/${RHEL_VERSION}/habanalabs-firmware-${HABANA_VERSION}.el8.${ARCH}.rpm | cpio -id \
    && cd /home/builder/habanalabs/usr/src/habanalabs-${HABANA_VERSION} \
    && make -j4 KVERSION=${KERNEL_VERSION}.${ARCH} GIT_SHA=${HABANA_GIT_SHA} \
    && xz drivers/misc/habanalabs/habanalabs.ko

FROM registry.access.redhat.com/ubi8/ubi-minimal@${BASE_DIGEST}

ARG ARCH="x86_64"
ARG HABANA_VERSION=""
ARG KERNEL_VERSION=""
ARG RHEL_VERSION=""
ARG BASE_DIGEST=""

LABEL io.k8s.description="Habana Labs Driver allows deploying matching driver / kernel versions on Kubernetes" \
      io.k8s.display-name="Habana Labs Driver" \
      io.openshift.release.operator=true \
      org.opencontainers.image.base.name="registry.access.redhat.com/ubi8/ubi:${RHEL_VERSION}" \
      org.opencontainers.image.base.digest="${BASE_DIGEST}" \
      org.opencontainers.image.source="https://github.com/HabanaAI/habana-ai-driver" \
      org.opencontainers.image.vendor="Habana Labs" \
      org.opencontainers.image.title="Habana Labs Driver" \
      org.opencontainers.image.description="Habana Labs Driver allows deploying matching driver / kernel versions on Kubernetes" \
      maintainer="Habana Labs" \
      name="habana-ai-driver" \
      vendor="Habana Labs" \
      version="${HABANA_VERSION}-${KERNEL_VERSION}.${ARCH}"

COPY --from=builder --chown=0:0 /home/builder/habanalabs/usr/src/habanalabs-${HABANA_VERSION}/drivers/misc/habanalabs/habanalabs.ko.xz /opt/lib/modules/${KERNEL_VERSION}.${ARCH}/extra/habanalabs.ko.xz
COPY --from=builder --chown=0:0 /home/builder/habanalabs/lib/firmware/habanalabs/gaudi /opt/firmware/habanalabs/gaudi
RUN microdnf install -y kmod util-linux && microdnf clean all \
    && touch /opt/lib/modules/${KERNEL_VERSION}.${ARCH}/modules.builtin \
    && touch /opt/lib/modules/${KERNEL_VERSION}.${ARCH}/modules.order

COPY entrypoint /usr/bin/entrypoint
COPY exitpoint /usr/bin/exitpoint
ENTRYPOINT ["/usr/bin/entrypoint"]
