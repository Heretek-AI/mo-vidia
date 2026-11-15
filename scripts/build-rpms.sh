#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_DIR="${ROOT_DIR}/review/open-gpu-kernel-modules"
UPSTREAM_URL="https://github.com/NVIDIA/open-gpu-kernel-modules.git"
UPSTREAM_REF=""
APPLY_PATCHES=0
WITH_BINARY_KMOD=0
KERNEL_UNAME="$(uname -r)"
MO_VIDIA_REL="${MO_VIDIA_REL:-1}"
OUT_DIR="${ROOT_DIR}/dist/rpms"
ARCH="$(uname -m)"

usage() {
    cat <<EOF
Usage: $(basename "$0") [options]

Options:
  --source-dir <dir>       Path to open-gpu-kernel-modules checkout (default: ./review/open-gpu-kernel-modules)
  --upstream-ref <ref>     Clone NVIDIA/open-gpu-kernel-modules at <ref> into a build workspace and apply patches
  --apply-patches          Apply patches/*.patch to --source-dir before building
  --with-binary-kmod       Also build pre-compiled binary kmod-nvidia-<kver>.rpm for the target kernel
  --kernel-uname <kver>    Target kernel version for --with-binary-kmod (default: running kernel $(uname -r))
  --release-num <n>        mo-vidia release counter (default: 1)
  --out-dir <dir>          Output directory for RPMs (default: ./dist/rpms)
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --source-dir)
            SOURCE_DIR="$(cd "$2" && pwd)"
            shift 2
            ;;
        --upstream-ref)
            UPSTREAM_REF="$2"
            shift 2
            ;;
        --apply-patches)
            APPLY_PATCHES=1
            shift
            ;;
        --with-binary-kmod)
            WITH_BINARY_KMOD=1
            shift
            ;;
        --kernel-uname)
            KERNEL_UNAME="$2"
            shift 2
            ;;
        --release-num)
            MO_VIDIA_REL="$2"
            shift 2
            ;;
        --out-dir)
            OUT_DIR="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown argument: $1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/mo-vidia-rpmbuild.XXXXXX")"
trap 'rm -rf "${WORK_DIR}"' EXIT

if [[ -n "${UPSTREAM_REF}" ]]; then
    echo "==> Cloning ${UPSTREAM_URL} @ ${UPSTREAM_REF}..."
    SOURCE_DIR="${WORK_DIR}/open-gpu-kernel-modules"
    git clone --depth 1 --branch "${UPSTREAM_REF}" "${UPSTREAM_URL}" "${SOURCE_DIR}"
    APPLY_PATCHES=1
fi

if [[ ! -f "${SOURCE_DIR}/version.mk" ]]; then
    echo "Error: ${SOURCE_DIR}/version.mk not found." >&2
    exit 1
fi

if [[ "${APPLY_PATCHES}" -eq 1 ]]; then
    echo "==> Applying mo-vidia patches from ${ROOT_DIR}/patches..."
    for patch_file in "${ROOT_DIR}"/patches/*.patch; do
        echo "  -> $(basename "${patch_file}")"
        git -C "${SOURCE_DIR}" apply --3way "${patch_file}"
    done
fi

UPSTREAM_VERSION="$(awk '/^NVIDIA_VERSION =/ {print $3}' "${SOURCE_DIR}/version.mk")"
if [[ -z "${UPSTREAM_VERSION}" ]]; then
    echo "Error: Could not parse NVIDIA_VERSION from ${SOURCE_DIR}/version.mk" >&2
    exit 1
fi

echo "==> Building mo-vidia RM core for NVIDIA_VERSION=${UPSTREAM_VERSION} (${ARCH})..."
make -C "${SOURCE_DIR}/src/nvidia" -j"$(nproc)"
make -C "${SOURCE_DIR}/src/nvidia-modeset" -j"$(nproc)"

NV_KERNEL_O="${SOURCE_DIR}/src/nvidia/_out/Linux_${ARCH}/nv-kernel.o"
NV_MODESET_O="${SOURCE_DIR}/src/nvidia-modeset/_out/Linux_${ARCH}/nv-modeset-kernel.o"

if [[ ! -f "${NV_KERNEL_O}" || ! -f "${NV_MODESET_O}" ]]; then
    echo "Error: Expected RM core binaries not found after build." >&2
    exit 1
fi

echo "==> Staging clean kernel-open tree and packaging kmodsrc tarball..."
STAGE_DIR="${WORK_DIR}/stage"
mkdir -p "${STAGE_DIR}"

# Copy tracked/clean kernel-open source files using git archive or rsync excluding build products
rsync -a \
    --exclude='*.o' \
    --exclude='*.ko' \
    --exclude='*.cmd' \
    --exclude='*.mod' \
    --exclude='*.mod.c' \
    --exclude='*.d' \
    --exclude='Module.symvers' \
    --exclude='modules.order' \
    --exclude='conftest' \
    --exclude='patches.h' \
    --exclude='nv-kernel.o_binary' \
    --exclude='nv-modeset-kernel.o_binary' \
    "${SOURCE_DIR}/kernel-open" "${STAGE_DIR}/"

install -m 0644 "${NV_KERNEL_O}" "${STAGE_DIR}/kernel-open/nvidia/nv-kernel.o_binary"
install -m 0644 "${NV_MODESET_O}" "${STAGE_DIR}/kernel-open/nvidia-modeset/nv-modeset-kernel.o_binary"

TOPDIR="${WORK_DIR}/rpmbuild"
mkdir -p "${TOPDIR}"/{BUILD,BUILDROOT,RPMS,SOURCES,SPECS,SRPMS}

TARBALL_PATH="${TOPDIR}/SOURCES/nvidia-kmod-${UPSTREAM_VERSION}-${ARCH}.tar.xz"
tar -C "${STAGE_DIR}" -cJf "${TARBALL_PATH}" kernel-open

cp -f "${ROOT_DIR}/rpm/nvidia-kmodtool-excludekernel-filterfile" "${TOPDIR}/SOURCES/"

sed \
    -e "s/%{!?upstream_version: %global upstream_version .*}/%global upstream_version ${UPSTREAM_VERSION}/" \
    -e "s/%{!?mo_vidia_rel: %global mo_vidia_rel .*}/%global mo_vidia_rel ${MO_VIDIA_REL}/" \
    "${ROOT_DIR}/rpm/xorg-x11-drv-nvidia-kmodsrc.spec" \
    > "${TOPDIR}/SPECS/xorg-x11-drv-nvidia-kmodsrc.spec"

sed \
    -e "s/%{!?upstream_version: %global upstream_version .*}/%global upstream_version ${UPSTREAM_VERSION}/" \
    -e "s/%{!?mo_vidia_rel: %global mo_vidia_rel .*}/%global mo_vidia_rel ${MO_VIDIA_REL}/" \
    "${ROOT_DIR}/rpm/nvidia-kmod.spec" \
    > "${TOPDIR}/SPECS/nvidia-kmod.spec"

echo "==> Building xorg-x11-drv-nvidia-kmodsrc RPM..."
rpmbuild -ba \
    --define "_topdir ${TOPDIR}" \
    "${TOPDIR}/SPECS/xorg-x11-drv-nvidia-kmodsrc.spec"

echo "==> Building akmod-nvidia and kmod-nvidia metapackage RPMs..."
rpmbuild -ba \
    --define "_topdir ${TOPDIR}" \
    --define "_without_kmodsrc_buildreq 1" \
    --define "kmodsrc_tarball ${TARBALL_PATH}" \
    "${TOPDIR}/SPECS/nvidia-kmod.spec"

if [[ "${WITH_BINARY_KMOD}" -eq 1 ]]; then
    echo "==> Building pre-compiled binary kmod-nvidia RPM for kernel ${KERNEL_UNAME}..."
    rpmbuild -bb \
        --define "_topdir ${TOPDIR}" \
        --define "_without_kmodsrc_buildreq 1" \
        --define "kmodsrc_tarball ${TARBALL_PATH}" \
        --define "kernels ${KERNEL_UNAME}" \
        "${TOPDIR}/SPECS/nvidia-kmod.spec"
fi

mkdir -p "${OUT_DIR}"
find "${TOPDIR}/RPMS" "${TOPDIR}/SRPMS" -type f -name "*.rpm" -exec cp -vf {} "${OUT_DIR}/" \;

if command -v createrepo_c >/dev/null 2>&1; then
    echo "==> Generating DNF repository metadata in ${OUT_DIR}..."
    createrepo_c --update "${OUT_DIR}"
fi

echo "==> Built RPM packages in ${OUT_DIR}:"
ls -lh "${OUT_DIR}"/*.rpm
