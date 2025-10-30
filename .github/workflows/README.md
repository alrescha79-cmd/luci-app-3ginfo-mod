# GitHub Actions Workflow for luci-app-3ginfo-lite

This repository uses GitHub Actions to automatically build IPK packages for multiple architectures.

## Setup Instructions

### 1. Enable Workflow Permissions

Before the workflow can run, you need to enable write permissions:

1. Go to your forked repository
2. Click **Settings**
3. Navigate to **Actions** → **General**
4. Scroll down to **Workflow permissions**
5. Select **Read and write permissions**
6. Check **Allow GitHub Actions to create and approve pull requests**
7. Click **Save**

### 2. Trigger the Workflow

The workflow will automatically run when:
- You push changes to the `main` branch
- Changes are made to `luci-app-3ginfo-lite/Makefile` (version bump)

You can also manually trigger it:
1. Go to **Actions** tab
2. Select **"Auto compile with OpenWrt SDK"**
3. Click **Run workflow**
4. Select branch `main`
5. Click **Run workflow**

## What Gets Built

The workflow builds IPK packages for three architectures:
- **x86_64** - For x86-based systems
- **aarch64** - For 64-bit ARM systems (arm64)
- **arm** - For 32-bit ARM systems (armv7)

## Version Management

The workflow checks for version changes in the Makefile:
- If `PKG_VERSION` in Makefile is different from the latest release tag
- A new release will be created automatically
- All IPK files will be uploaded to the release

### To create a new release:

1. Edit `luci-app-3ginfo-lite/Makefile`
2. Update `PKG_VERSION` (e.g., from `1.0.8` to `1.0.9`)
3. Update `PKG_RELEASE` with current date (e.g., `20251030`)
4. Commit and push:
   ```bash
   git add luci-app-3ginfo-lite/Makefile
   git commit -m "Bump version to 1.0.9"
   git push origin main
   ```
5. GitHub Actions will automatically:
   - Detect version change
   - Create new tag (e.g., `v1.0.9`)
   - Build IPK for all architectures
   - Create release with all IPK files

## Release Files

Each release will contain:
```
release-files/
├── x86_64/
│   ├── luci-app-3ginfo-lite_*.ipk
│   └── luci-i18n-3ginfo-lite-*.ipk
├── aarch64/
│   ├── luci-app-3ginfo-lite_*.ipk
│   └── luci-i18n-3ginfo-lite-*.ipk
└── arm/
    ├── luci-app-3ginfo-lite_*.ipk
    └── luci-i18n-3ginfo-lite-*.ipk
```

## Installation

After release is created, users can install by downloading the appropriate IPK:

```bash
# Download IPK for your architecture
wget https://github.com/alrescha79-cmd/luci-app-3ginfo-mod/releases/download/v1.0.8/luci-app-3ginfo-lite_*.ipk

# Install
opkg update
opkg install luci-app-3ginfo-lite_*.ipk
```

## OpenWrt SDK Versions

The workflow uses OpenWrt SDK version **24.10.0**:
- x86_64: `openwrt-sdk-24.10.0-x86-64_gcc-13.3.0_musl`
- aarch64: `openwrt-sdk-24.10.0-armsr-armv8_gcc-13.3.0_musl`
- arm: `openwrt-sdk-24.10.0-armsr-armv7_gcc-13.3.0_musl_eabihf`

## Cache

The workflow caches OpenWrt SDK downloads to speed up subsequent builds:
- Cache is stored per architecture
- Cache key: `openwrt-sdk-24.10.0-<arch>`
- If cache exists, SDK download is skipped

## Troubleshooting

### Workflow fails with "Permission denied"
- Check workflow permissions in Settings → Actions → General
- Enable "Read and write permissions"

### No new release created
- Check if version in Makefile is different from latest release tag
- Workflow only creates release if version has changed

### Build fails
- Check Actions tab for detailed logs
- Common issues:
  - Missing dependencies in Makefile
  - Syntax errors in source files
  - OpenWrt SDK compatibility issues

## Manual Build (without GitHub Actions)

If you want to build locally:

```bash
# Download OpenWrt SDK
wget https://archive.openwrt.org/releases/24.10.0/targets/x86/64/openwrt-sdk-24.10.0-x86-64_gcc-13.3.0_musl.Linux-x86_64.tar.zst

# Extract
tar --zstd -xvf openwrt-sdk-24.10.0-x86-64_gcc-13.3.0_musl.Linux-x86_64.tar.zst
cd openwrt-sdk-24.10.0-x86-64_gcc-13.3.0_musl.Linux-x86_64

# Setup feeds
echo "src-git base https://github.com/openwrt/openwrt.git;main" > feeds.conf
echo "src-git-full packages https://github.com/openwrt/packages.git;master" >> feeds.conf
echo "src-git-full luci https://github.com/openwrt/luci.git;master" >> feeds.conf
./scripts/feeds update -a

# Link package
ln -s /path/to/luci-app-3ginfo-lite package/

# Configure
echo "CONFIG_PACKAGE_luci-app-3ginfo-lite=m" >> .config
make defconfig

# Build
make package/luci-app-3ginfo-lite/{clean,compile} -j$(nproc)

# Find IPK
find bin/packages/ -name "*.ipk"
```
