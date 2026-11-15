# mo-vidia — Optimized NVIDIA Open GPU Kernel Modules

`mo-vidia` provides a high-performance kernel optimization patchset and automated Fedora / RPM Fusion RPM packaging pipeline for [`NVIDIA/open-gpu-kernel-modules`](https://github.com/NVIDIA/open-gpu-kernel-modules).

## Kernel Optimizations Included

1. **VRAM Physical Fragmentation & Premature OOM Prevention** (`video_mem.c`, `mem_mgr_gm107.c`):
   - **Non-Contiguous-First PMA Allocation**: Allocates non-contiguous physical VRAM frames immediately when `NVOS32_ATTR_PHYSICALITY_ALLOW_NONCONTIGUOUS` is set on non-NUMA discrete GPUs, preserving 2 MB contiguous physical blocks and avoiding failed-contiguous + Copy Engine scrubber stalls.
   - **2 MB $\rightarrow$ 64 KB Page Size Fallback**: Automatically falls back from `RM_PAGE_SIZE_2M` to `RM_PAGE_SIZE_64K` when a default-page-size $\ge 2\text{ MB}$ VRAM allocation fails 2 MB PMA allocation due to physical fragmentation.
   - **Graceful Hardware Compression (`comptag`) Fallback**: Falls back to an uncompressed PTE kind (`NVOS32_ATTR_COMPR_NONE`) when `kmemsysAllocComprResources_HAL` exhausts compression resources under heavy VRAM pressure instead of failing the allocation.
2. **Fast VRAM Recycling (`PMA_FREE_SKIP_SCRUB`)** (`mem_mgr.c`):
   - Skips asynchronous Copy Engine scrubbing on free for non-compressible surfaces on non-CC/non-MIG systems while preserving full hardware comptag scrubbing for compressible surfaces.
3. **64 KB Large & 2 MB Huge System Memory Pages & Pools on Discrete GPUs** (`g_mem_mgr_nvoc.c`, `mem_mgr.c`, `system_mem.c`, `virt_mem_allocator_gm107.c`):
   - Enables `bSysmemPageSizeDefaultAllowLargePages = NV_TRUE` and `bAllowSysmemHugePages = NV_TRUE` across all discrete GPU architectures (`TU102..AD107`+).
   - Selects 2 MB (order-9) and 64 KB (order-4) compound pages for aligned system memory allocations, activating the high-order `sysmem_page_pools` and reducing PCIe GMMU page table entries by $16\times$–$512\times$.
4. **Zero-IPI Cache-Type-Aware (`WB` vs `UC`/`WC`) Page Pools** (`nv-vm.c`):
   - Retains `NV_MEMORY_WRITECOMBINE` / `NV_MEMORY_UNCACHED` PAT state inside dedicated `uc_clean_list` and `uc_dirty_list` pools in `nv_page_pool_t`, eliminating synchronous cross-core CPU IPI TLB/cache shootdowns (`cpa_flush` via `set_memory_array_uc` / `set_memory_array_wb`) when recycling staging buffers.
   - Keeps `sysmem_page_pools` active when `NVreg_InitializeSystemMemoryAllocations=0`.
5. **Default PCIe & BAR1 Performance Parameters** (`nv-reg.h`):
   - `NVreg_EnableResizableBar = 1` (enables Static BAR1 full-VRAM mapping when Resizable BAR is supported)
   - `NVreg_EnablePCIERelaxedOrderingMode = 1`
   - `NVreg_EnableStreamMemOPs = 1`
   - `NVreg_InitializeSystemMemoryAllocations = 0`
   - `NVreg_PreserveVideoMemoryAllocations = 1` & `/var/tmp` temporary file path for Fedora SELinux compatibility.

---

## Installing RPM Packages on Fedora (Drop-in RPM Fusion Replacement)

The built packages (`xorg-x11-drv-nvidia-kmodsrc`, `akmod-nvidia`, and `kmod-nvidia`) use `Epoch: 3` and `Release: 100.mo_vidia.*`, acting as a drop-in upgrade over RPM Fusion's kernel module packages while preserving full compatibility with RPM Fusion's `xorg-x11-drv-nvidia`, `xorg-x11-drv-nvidia-cuda`, and `nvidia-settings` userspace packages.

### Option 1: Install from the Automated DNF Repository (GitHub Pages)

```bash
sudo dnf config-manager addrepo --from-repofile=https://heretek-ai.github.io/mo-vidia/mo-vidia.repo
sudo dnf upgrade -y xorg-x11-drv-nvidia-kmodsrc akmod-nvidia
sudo akmods --force
```

### Option 2: Install Directly from Local Build or GitHub Releases

```bash
sudo dnf install -y ./dist/rpms/*.x86_64.rpm
```

---

## Building RPMs Locally

```bash
# Build xorg-x11-drv-nvidia-kmodsrc, akmod-nvidia, and binary kmod-nvidia-$(uname -r) RPMs:
./scripts/build-rpms.sh --with-binary-kmod

# Or clone a specific upstream NVIDIA/open-gpu-kernel-modules tag, apply patches, and build RPMs:
./scripts/build-rpms.sh --upstream-ref 595 --with-binary-kmod
```

Built `.rpm` and `.src.rpm` packages are written to `dist/rpms/`.
