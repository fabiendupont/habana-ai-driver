#!/usr/bin/env bash

PULL_SECRET_FILE="${PULL_SECRET_FILE:-/pull-secret}"
echo "Getting pull secret from ${PULL_SECRET_FILE}"

MATRIX_FILE="build-matrix.json"
echo "Generating matrix in ${MATRIX_FILE}"

# TODO: Use an external matrix for HABANA drivers
HABANA_VERSIONS=("1.6.0-439")

# Retrieve all the unique kernel versions
KVERS=()
declare -A KVERS_OCPVERS_MAP
for y in $(seq 12 12); do
    # The curl command will reteive all builds for 4.y openshift releace (4.y.0 4.y.1 ...)
    for z in $(curl -s https://mirror.openshift.com/pub/openshift-v4/clients/ocp/ | grep -Eo "4\.${y}\.[0-9]+" | sort -uV); do
        for a in "x86_64"; do
            # Get the release image for the z-stream
            echo -n "Get the release image for OCP ${z}-${a}."
            IMG=$(oc adm release info --image-for=machine-os-content quay.io/openshift-release-dev/ocp-release:${z}-${a} 2>/dev/null)

    	    # Get the image info in JSON format, so we can use jq on it
            IMG_INFO=$(oc image info -o json -a ${PULL_SECRET_FILE} ${IMG} 2>/dev/null)

            # If the command failed, we skip the kernel lookup.
            [ $? != 0 ] && echo "Image info for OCP ${z}-${a} not available" && continue

            # Add the kernel version from the image labels to the list of kernels
            KVER=$(echo ${IMG_INFO} | jq -r ".config.config.Labels[\"com.coreos.rpm.kernel-rt-core\"]" | sed -r "s/^(.*)\.rt.*(el[0-9]+.*).${a}/\1.\2/")
            if [[ ! ${KVERS_OCPVERS_MAP[${KVER}]} ]]; then
                KVERS_OCPVERS_MAP[${KVER}]=${z}
            fi
            KVERS+=( ${KVER} )
            echo " Kernel version for OCP ${z}-${a} is ${KVER}.${a}."
        done
    done
done

# Remove duplicates from the list of kernels and sort it
IFS=" " read -r -a KVERS <<< "$(tr ' ' '\n' <<< "${KVERS[@]}" | sort -u | tr '\n' ' ')"

# Initialize the matrix file
echo "{" > ${MATRIX_FILE}
echo "    \"versions\": [" >> ${MATRIX_FILE}

# Build the matrix from the list of kernel versions
LAST_KVER=""
COUNT=0
for KVER in ${KVERS[@]}; do
    # Extract RHEL version from the kernel version
    RHEL_VERSION=$(echo ${KVER} | rev | cut -d "." -f 1 | rev | sed -e "s/^el//" -e "s/_/./")

    # Retrieve UBI image digest for RHEL version
    UBI_DIGEST=$(oc image info -o json --filter-by-os "linux/amd64" registry.access.redhat.com/ubi8/ubi-minimal:${RHEL_VERSION} 2>/dev/null | jq -r '.digest')

    # Initialize the arch with "x86_64" which is mandatory
    ARCH="linux/amd64"
    ARCH_TAG="x86_64"

    # Generate the matrix entries for the kernel x drivers
    for HL_VER in ${HABANA_VERSIONS[@]}; do
        # Check if a habana-ai-driver image exists for this driver and kernel versions
        BUILD_NEEDED="true"
        DRV_IMG=$(oc image info -a ${PULL_SECRET_FILE} -o json --filter-by-os "linux/amd64" ghcr.io/fabiendupont/habana-ai-driver:${HL_VER}-${KVER}.${ARCH_TAG} 2>/dev/null)
        if [ $? == 0 ]; then
            echo "Habana AI Driver image for ${HL_VER}-${KVER}.${ARCH_TAG} exists. Checking if base image has changed."
            OLD_UBI_DIGEST=$(echo "${DRV_IMG}" | jq -r ".config.config.Labels[\"org.opencontainers.image.base.digest\"]")
            if [ "${OLD_UBI_DIGEST}" == "${CUR_UBI_DIGEST}" ]; then
                echo "The UBI ${RHEL_VERSION} has not changed. No need to build."
                BUILD_NEEDED="false"
            fi
        fi

        if [ "${BUILD_NEEDED}" == "true" ]; then
            # Get openshift driver toolkit for the kernel version
            DRIVER_TOOLKIT_IMAGE=$(oc adm release info ${KVERS_OCPVERS_MAP[${KVER}]} --image-for=driver-toolkit 2>/dev/null)

            # Add a comma for all entries but the first one
            [ ${COUNT} -gt 0 ] && echo "," >> ${MATRIX_FILE}

            # Add a line for kernel x driver
            echo "        {" >> ${MATRIX_FILE}
            echo "            \"rhel\": \"${RHEL_VERSION}\"," >> ${MATRIX_FILE}
            echo "            \"ubi-digest\": \"${UBI_DIGEST}\"," >> ${MATRIX_FILE}
            echo "            \"kernel\": \"${KVER}\"," >> ${MATRIX_FILE}
            echo "            \"driver\": \"${HL_VER}\"," >> ${MATRIX_FILE}
            echo "            \"arch\": \"${ARCH}\"," >> ${MATRIX_FILE}
            echo "            \"arch_tag\": \"${ARCH_TAG}\"," >> ${MATRIX_FILE}
            echo "            \"driver-toolkit-image\": \"${DRIVER_TOOLKIT_IMAGE}\"" >> ${MATRIX_FILE}
            echo -n "        }" >> ${MATRIX_FILE}

            # Increment counter
            ((COUNT++))
	fi
    done
done

# Finalize the matrix file
echo >> ${MATRIX_FILE}
echo "    ]" >> ${MATRIX_FILE}
echo -n "}" >> ${MATRIX_FILE}
