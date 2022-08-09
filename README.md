# Habana AI Driver Container

This repository contains everything needed to build a container image with a
precompiled Habana AI driver. It requires to know the kernel version, since it
builds and installs the driver package for a given kernel.

The image creation uses a multi-stage approach that leverages the
[driver-toolkit](https://github.com/smgglrs/driver-toolkit) container image to
build the kernel module, then install the module in the final image, along with
kernel module management packages.

## Manual build of the container image

Below is an example for building a driver image for the version `1.4.1-11` of
the Habana AI driver and the version `4.18.0-348.2.1.el8_5` of the kernel.

```shell
export ARCH="x86_64"
export BASE_DIGEST="sha256:6e79406e33049907e875cb65a31ee2f0575f47afa0f06e3a2a9316b01ee379eb"
export HABANA_VERSION="1.4.1-11"
export HABANA_GIT_SHA="1f3054c"
export KERNEL_VERSION="4.18.0-372.19.1.el8_6"
export RHEL_VERSION="8.6"
```

```shell
podman build \
    --build-arg ARCH=x86_64 \
    --build-arg BASE_DIGEST=${BASE_DIGEST} \
    --build-arg HABANA_VERSION=${HABANAVERSION} \
    --build-arg HABANA_GIT_SHA=${HABANA_GIT_SHA} \
    --build-arg KERNEL_VERSION=${KERNEL_VERSION} \
    --build-arg RHEL_VERSION=${RHEL_VERSION} \
    --tag ghcr.io/fabiendupont/habana-ai-driver:${HABANA_VERSION}-${KERNEL_VERSION} \
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
podman push ghcr.io/fabiendupont/habana-ai-driver:${DRIVER_VERSION}-${KERNEL_VERSION}
```

## Maintain a library of Habana AI driver images

<mark>TODO</mark>
