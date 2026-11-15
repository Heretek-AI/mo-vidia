%global debug_package %{nil}
%{!?upstream_version: %global upstream_version 620.70.06}
%{!?mo_vidia_rel: %global mo_vidia_rel 1}

Name:           xorg-x11-drv-nvidia-kmodsrc
Epoch:          3
Version:        %{upstream_version}
Release:        100.mo_vidia.%{mo_vidia_rel}%{?dist}
Summary:        mo-vidia optimized NVIDIA open GPU kernel module source tree
License:        Dual MIT/GPL
URL:            https://github.com/Heretek-AI/mo-vidia

Source0:        nvidia-kmod-%{version}-%{_target_cpu}.tar.xz

ExclusiveArch:  x86_64 aarch64

Provides:       rpm_macro(nvidia_kmodsrc_version)

%description
Source tree and pre-compiled Resource Manager core binaries (nv-kernel.o_binary
and nv-modeset-kernel.o_binary) with mo-vidia VRAM, PMA, GMMU, 64KB/2MB sysmem
large-page, PAT cache-type pool, and PCIe/Resizable BAR optimizations for building
nvidia-kmod packages via akmods.

%prep
# No unpack needed; tarball is installed directly for akmods consumption

%build
# Nothing to build here; nv-kernel.o_binary is pre-built into Source0

%install
install -d -m 0755 %{buildroot}%{_datadir}/nvidia-kmod-%{version}
install -p -m 0644 %{SOURCE0} %{buildroot}%{_datadir}/nvidia-kmod-%{version}/nvidia-kmod-%{version}-%{_target_cpu}.tar.xz

install -d -m 0755 %{buildroot}%{_rpmmacrodir}
cat > %{buildroot}%{_rpmmacrodir}/macros.xorg-x11-drv-nvidia-kmodsrc <<EOF
# nvidia_kmodsrc_version RPM Macro
%%nvidia_kmodsrc_version	%{version}
EOF

%files
%dir %{_datadir}/nvidia-kmod-%{version}
%{_datadir}/nvidia-kmod-%{version}/nvidia-kmod-%{version}-%{_target_cpu}.tar.xz
%{_rpmmacrodir}/macros.xorg-x11-drv-nvidia-kmodsrc

%changelog
* Sun Nov 15 2026 mo-vidia CI <noreply@github.com> - 3:%{upstream_version}-100.mo_vidia.%{mo_vidia_rel}
- Build mo-vidia optimized open-gpu-kernel-modules kmodsrc package
