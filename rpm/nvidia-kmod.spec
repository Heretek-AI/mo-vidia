%if 0%{?fedora}
%global buildforkernels akmod
%endif
%global debug_package %{nil}
%{!?upstream_version: %global upstream_version 620.70.06}
%{!?mo_vidia_rel: %global mo_vidia_rel 1}

# Build flags are inherited from the kernel
%undefine _auto_set_build_flags

Name:           nvidia-kmod
Epoch:          3
Version:        %{upstream_version}
# Taken over by kmodtool
Release:        100.mo_vidia.%{mo_vidia_rel}%{?dist}
Summary:        mo-vidia optimized NVIDIA open GPU kernel modules
License:        Dual MIT/GPL
URL:            https://github.com/Heretek-AI/mo-vidia

Source11:       nvidia-kmodtool-excludekernel-filterfile

ExclusiveArch:  x86_64 aarch64

%global AkmodsBuildRequires %{_bindir}/kmodtool, %{_bindir}/lspci, %{_bindir}/pahole, xorg-x11-drv-nvidia-kmodsrc = %{epoch}:%{version}
%if 0%{!?_without_kmodsrc_buildreq:1}
BuildRequires:  %{AkmodsBuildRequires}
%endif
BuildRequires:  gcc, elfutils-libelf-devel

%{!?kmodsrc_tarball: %global kmodsrc_tarball %{_datadir}/%{name}-%{version}/%{name}-%{version}-%{_target_cpu}.tar.xz}

# kmodtool generates akmod-nvidia and/or kmod-nvidia-<kver> subpackages
%{expand:%(kmodtool --target %{_target_cpu} --repo rpmfusion --kmodname %{name} --filterfile %{SOURCE11} --obsolete-name nvidia-newest --obsolete-version "%{?epoch}:%{version}-%{release}" %{?buildforkernels:--%{buildforkernels}} %{?kernels:--for-kernels "%{?kernels}"} 2>/dev/null) }

%description
mo-vidia optimized NVIDIA %{version} open GPU kernel modules for kernel %{kversion}.
Includes non-contiguous-first PMA allocation, 2MB->64KB VRAM fragmentation fallback,
64KB/2MB sysmem large/huge pages, cache-type-aware PAT page pools (zero IPI TLB
shootdowns on WC/UC staging buffers), skip-scrub-on-free for non-compressible buffers,
and default Resizable BAR / Static BAR1 / PCIe Relaxed Ordering / StreamMemOPs.

%prep
%{?kmodtool_check}
kmodtool --target %{_target_cpu} --repo rpmfusion --kmodname %{name} --filterfile %{SOURCE11} --obsolete-name nvidia-newest --obsolete-version "%{?epoch}:%{version}-%{release}" %{?buildforkernels:--%{buildforkernels}} %{?kernels:--for-kernels "%{?kernels}"} 2>/dev/null
%setup -T -c
tar --use-compress-program xz -xf %{kmodsrc_tarball}

if [ -d kernel-open ] && [ ! -d kernel ]; then
    mv kernel-open kernel
elif [ -d kernel-open ] && [ -d kernel ]; then
    rm -rf kernel
    mv kernel-open kernel
fi

for kernel_version in %{?kernel_versions} ; do
    cp -a kernel _kmod_build_${kernel_version%%___*}
done

%build
%if 0%{?_without_nvidia_uvm:1}
export NV_EXCLUDE_KERNEL_MODULES="${NV_EXCLUDE_KERNEL_MODULES} nvidia_uvm "
%endif
%if 0%{?_without_nvidia_modeset:1}
export NV_EXCLUDE_KERNEL_MODULES="${NV_EXCLUDE_KERNEL_MODULES} nvidia_modeset "
%endif

for kernel_version in %{?kernel_versions}; do
  pushd _kmod_build_${kernel_version%%___*}/
    %make_build \
        KERNEL_UNAME="${kernel_version%%___*}" SYSSRC="${kernel_version##*___}" \
        IGNORE_CC_MISMATCH=1 IGNORE_XEN_PRESENCE=1 IGNORE_PREEMPT_RT_PRESENCE=1 \
        modules
  popd
done

%install
for kernel_version in %{?kernel_versions}; do
    mkdir -p $RPM_BUILD_ROOT/%{kmodinstdir_prefix}/${kernel_version%%___*}/%{kmodinstdir_postfix}/
    install -D -m 0755 _kmod_build_${kernel_version%%___*}/nvidia*.ko \
         $RPM_BUILD_ROOT/%{kmodinstdir_prefix}/${kernel_version%%___*}/%{kmodinstdir_postfix}/
done
%{?akmod_install}

%changelog
* Sun Nov 15 2026 mo-vidia CI <noreply@github.com> - 3:%{upstream_version}-100.mo_vidia.%{mo_vidia_rel}
- Build mo-vidia optimized open-gpu-kernel-modules akmod and kmod packages
