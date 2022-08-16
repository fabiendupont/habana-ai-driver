# Habana AI Driver Container

This repository contains everything needed to build a container image with a
precompiled Habana AI driver. It requires to know the kernel version, since it
builds and installs the driver package for a given kernel.

The image creation uses a multi-stage approach that leverages the
[driver-toolkit](https://github.com/smgglrs/driver-toolkit) container image to
build the kernel module, then install the module in the final image, along with
kernel module management packages.

## Manual build of the container image

Below is an example for building a driver image for the version `1.6.0-439` of
the Habana AI driver and the version `4.18.0-372.19.1.el8_6` of the kernel.

```shell
export ARCH="x86_64"
export HABANA_VERSION="1.6.0-439"
export KERNEL_VERSION="4.18.0-372.19.1.el8_6"
```

We are using `ubi8/ubi-minimal` as the base image for our driver container.
More precisely, we're using version `8.6` to match the kernel version. For
a better traceability, we store the base image digest in the driver container
image labels. So, we need to retrieve the SHA256 digest of the
`ubi8/ubi-minimal:8.6` image. For that, we use `curl` to get the image manifest
headers that contains the digest in the redirect URL.

```shell
export RHEL_VERSION="8.6"
export BASE_DIGET=$(curl -sI \
    -H "Accept: application/vnd.docker.distribution.manifest.v2+json" \
    "https://registry.access.redhat.com/v2/ubi8/ubi-minimal/manifests/${RHEL_VERSION}" \
    | grep -i "^Location: " | rev | cut -d '/' -f 1 | rev)
```

We also need the Git digest of the commit used by Habana AI to build the driver
RPM. We can extract it from the DKMS configuration file shipped within the RPM.
We use `rpm2cpio` and `cpio` to read the `dkms.conf` file.

```shell
export HABANA_GIT_SHA=$(rpm2cpio \
    https://vault.habana.ai/artifactory/rhel/8/${RHEL_VERSION}/habanalabs-${HABANA_VERSION}.el8.noarch.rpm \
    | cpio -i --to-stdout ./usr/src/habanalabs-${HABANA_VERSION}/dkms.conf 2>/dev/null \
    | grep "KMD_LAST_GIT_SHA=" | cut -d "=" -f 2)
```

With all these variables set, we can now proceed to building the driver
container image with `podman build`. 

```shell
podman build \
    --build-arg ARCH=${ARCH} \
    --build-arg BASE_DIGEST=${BASE_DIGEST} \
    --build-arg HABANA_VERSION=${HABANA_VERSION} \
    --build-arg HABANA_GIT_SHA=${HABANA_GIT_SHA} \
    --build-arg KERNEL_VERSION=${KERNEL_VERSION} \
    --build-arg RHEL_VERSION=${RHEL_VERSION} \
    --tag ghcr.io/fabiendupont/habana-ai-driver:${HABANA_VERSION}-${KERNEL_VERSION}.${ARCH} \
    --file Dockerfile .
```

The resulting container image is much smaller than the `driver-toolkit` image,
with only 143 MB. We could get a smaller image with `ubi8/ubi-micro` base
image, but that would require more hacks to install the kernel module
management commands.

For that image to be usable in our OpenShift clusters, we simply push it to
ghcr.io.

```shell
podman login ghcr.io
podman push ghcr.io/fabiendupont/habana-ai-driver:${HABANA_VERSION}-${KERNEL_VERSION}.${ARCH}
```

## Maintain a library of Habana AI driver images

<mark>TODO</mark>
