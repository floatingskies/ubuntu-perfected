# ubuntu-perfected

A bootc-enabled Ubuntu image with ubuntu-desktop, based on the Universal Blue template principles. This image provides a bootable container environment running Ubuntu with a full desktop experience.

> A pure Ubuntu bootc image with desktop capabilities.

## What's Included

### Build System
- Automated builds via GitHub Actions on every commit
- Self-hosted Renovate setup that keeps all your images and actions up to date
- Automatic cleanup of old images (90+ days) to keep it tidy
- Pull request workflow - test changes before merging to main
  - PRs build and validate before merge
  - `main` branch builds `:stable` images
- Validates your files on pull requests:
  - Brewfile, Justfile, ShellCheck, Renovate config, and flatpak validation
- Production Grade Features
  - Container signing, SBOM Generation, and layer rechunking (optional)
  - See checklist below to enable these as they take some manual configuration

### Ubuntu Desktop
- Full ubuntu-desktop package installed
- Based on ghcr.io/bootcrew/ubuntu-bootc:latest
- Bootable container image for Ubuntu

### Homebrew Integration
- Pre-configured Brewfiles for easy package installation and customization
- Users install packages at runtime with `brew bundle`
- See [custom/brew/](custom/brew/) for details

### Flatpak Support
- Ship your favorite flatpaks
- Automatically installed on first boot after user setup
- See [custom/flatpaks/](custom/flatpaks/) for details

### ujust Commands
- User-friendly command shortcuts via `ujust`
- Pre-configured examples for app installation and system maintenance
- See [custom/ujust/](custom/ujust/) for details

### Build Scripts
- Modular numbered scripts (10-, 20-, 30-) run in order
- Located in [build/](build/) directory
- 10-build.sh installs ubuntu-desktop and configures the system

## Quick Start

### 1. Enable GitHub Actions

This repository comes with GitHub Actions workflows ready to go:

- Go to the "Actions" tab in your repository
- Click "I understand my workflows, go ahead and enable them"

Your first build will start automatically! 

Note: Image signing is disabled by default. Your images will build successfully without any signing keys. Once you're ready for production, see "Optional: Enable Image Signing" below.

### 2. Customize Your Image

The base image is defined in `Containerfile`:
```dockerfile
FROM ghcr.io/bootcrew/ubuntu-bootc:latest
```

Add your packages in `build/10-build.sh`:
```bash
apt-get install -y package-name
```

Customize your apps:
- Add Brewfiles in `custom/brew/`
- Add Flatpaks in `custom/flatpaks/`
- Add ujust commands in `custom/ujust/`

### 3. Development Workflow

All changes should be made via pull requests:

1. Open a pull request on GitHub with the change you want
2. The PR will automatically trigger:
   - Build validation
   - Brewfile, Flatpak, Justfile, and shellcheck validation
   - Test image build
3. Once checks pass, merge the PR
4. Merging triggers publication of a `:stable` image

### 4. Deploy Your Image

Switch to your image:
```bash
sudo bootc switch ghcr.io/castrojo/ubuntu-perfected:stable
sudo systemctl reboot
```

## Optional: Enable Image Signing

Image signing is disabled by default to let you start building immediately. However, signing is strongly recommended for production use.

### Why Sign Images?

- Verify image authenticity and integrity
- Prevent tampering and supply chain attacks
- Required for some enterprise/security-focused deployments
- Industry best practice for production images

### Setup Instructions

1. **Generate signing keys:**
```bash
cosign generate-key-pair
```

This creates two files:
- `cosign.key` (private key) - Keep this secret!
- `cosign.pub` (public key) - Commit this to your repository

2. **Add the private key to GitHub Secrets:**
   - Copy the entire contents of `cosign.key`
   - Go to your repository on GitHub
   - Navigate to Settings → Secrets and variables → Actions
   - Click "New repository secret"
   - Name: `SIGNING_SECRET`
   - Value: Paste the entire contents of `cosign.key`
   - Click "Add secret"
   
   For detailed instructions, see [GitHub's documentation on encrypted secrets](https://docs.github.com/en/actions/security-guides/encrypted-secrets#creating-encrypted-secrets-for-a-repository).

3. **Replace the contents of `cosign.pub` with your public key:**
   - Open `cosign.pub` in your repository
   - Replace the placeholder with your actual public key
   - Commit and push the change

4. **Enable signing in the workflow:**
   - Edit `.github/workflows/build.yml`
   - Find the "OPTIONAL: Image Signing with Cosign" section
   - Uncomment the steps to install Cosign and sign the image
   - Commit and push the change

5. **Your next build will produce signed images!**

**Important:** Never commit `cosign.key` to the repository. It's already in `.gitignore`.

## Production Features

Ready to take your custom OS to production? Enable these features for enhanced security, reliability, and performance:

### Production Checklist

- [ ] **Enable Image Signing** (Recommended)
  - Provides cryptographic verification of your images
  - Prevents tampering and ensures authenticity
  - See "Optional: Enable Image Signing" section above
  - Status: **Disabled by default**

- [ ] **Enable Rechunker** (Recommended)
  - Optimizes image layer distribution for better download resumability
  - Improves reliability for users with unstable connections
  - To enable:
    1. Edit `.github/workflows/build.yml`
    2. Find the "Rechunk (OPTIONAL)" section
    3. Uncomment the "Run Rechunker" step
    4. Uncomment the "Load in podman and tag" step
    5. Comment out the "Tag for registry" step that follows
    6. Commit and push
  - Status: **Disabled by default**

- [ ] **Enable SBOM Attestation** (Recommended)
  - Generates Software Bill of Materials for supply chain security
  - Provides transparency about what's in your image
  - Requires image signing to be enabled first
  - To enable:
    1. First complete image signing setup above
    2. Edit `.github/workflows/build.yml`
    3. Find the "OPTIONAL: SBOM Attestation" section
    4. Uncomment the setup and generation steps
    5. Commit and push
  - Status: **Disabled by default**

### After Enabling Production Features

Your workflow will:
- Sign all images with your key
- Generate and attach SBOMs
- Optimize layers for better distribution
- Provide full supply chain transparency

Users can verify your images with:
```bash
cosign verify --key cosign.pub ghcr.io/castrojo/ubuntu-perfected:stable
```

## Local Testing

Test your changes before pushing:

```bash
just build              # Build container image
just build-qcow2        # Build VM disk image
just run-vm-qcow2       # Test in browser-based VM
```

## Project Structure

```
ubuntu-perfected/
├── Containerfile              # Main build definition
├── Justfile                   # Local build commands
├── artifacthub-repo.yml       # ArtifactHub metadata
├── cosign.pub                 # Public signing key
├── .github/
│   ├── workflows/             # GitHub Actions
│   │   ├── build.yml          # Main build workflow
│   │   ├── clean.yml          # Cleanup old images
│   │   ├── renovate.yml       # Auto-updates
│   │   └── validate-*.yml     # Validation workflows
│   └── renovate.json5         # Renovate configuration
├── build/
│   └── 10-build.sh            # Install ubuntu-desktop
├── custom/
│   ├── brew/                  # Homebrew packages
│   ├── flatpaks/              # Flatpak applications
│   └── ujust/                 # User commands
└── iso/
    ├── disk.toml              # Disk image config
    └── iso.toml               # ISO installer config
```

## Ubuntu-Specific Notes

This image is based on Ubuntu bootc, not Fedora. Key differences:

- **Package Manager**: Uses `apt`/`apt-get` instead of `dnf`
- **Desktop Environment**: Installs `ubuntu-desktop`
- **Base Image**: Uses `ghcr.io/bootcrew/ubuntu-bootc:latest`

> **Package manager state**: The ubuntu-bootc base image ships with an empty
> `/var` — bootcrew's build wipes it, *including the entire dpkg database* — so
> apt/dpkg would otherwise have no idea what is installed in `/usr`. This image
> fixes that in the `Containerfile`:
>
> - An `apt-state` build stage replays bootcrew's own base-build recipe against
>   the Ubuntu archive snapshot matching the base image's `/usr` content
>   (see the `APT_SNAPSHOT` build arg), producing a **byte-accurate dpkg
>   database** for everything already baked into `/usr`.
> - The main stage imports that database (`COPY --from=apt-state
>   /var/lib/dpkg /var/lib/dpkg`), so `apt list --installed`, `apt upgrade` and
>   `apt install` behave like a regular Ubuntu machine, including on the booted
>   system (bootc's `/var` persists).
> - Because base packages are recorded as already installed, reinstalling them
>   (e.g. desktop dependencies that overlap the base) is an *upgrade*, and dpkg
>   **preserves the base's conffile customizations** (e.g.
>   `/etc/default/useradd` keeps `HOME=/var/home`).
> - See `build/10-build.sh`: it recreates `/var/lib/apt/lists/partial`,
>   verifies the imported database matches the baked kernel (fails loudly if
>   `APT_SNAPSHOT` goes stale), **holds all `linux-*` kernel packages** (so apt
>   can never rebuild initramfs without the bootc dracut module and leave the
>   machine unbootable — kernel updates belong in the base image), upgrades the
>   rest of the base to the current archive, then installs
>   `ubuntu-desktop-minimal`.
>
> **Upstream caveat**: the bootcrew base image's `/usr` was built from an
> archive state of mid-2026 (its `latest` is no longer rebuilt regularly). The
> `apt-get upgrade` step above converges most of the base to the current
> archive at build time; anything else can be brought up to date on the booted
> machine with the usual `sudo apt update && sudo apt upgrade` (kernel packages
> stay held by design). If the upstream base is rebuilt with a newer `/usr`,
> bump `APT_SNAPSHOT` to the archive state matching it — the build's coherence
> check tells you exactly when.

Example package installation in `build/10-build.sh`:
```bash
# Ubuntu/Debian
apt-get update
apt-get install -y package-name

# vs Fedora
# dnf5 install -y package-name
```

## Community

- [Universal Blue Forums](https://universal-blue.discourse.group/)
- [Universal Blue Discord](https://discord.gg/WEu6BdFEtp)
- [bootc Discussion](https://github.com/bootc-dev/bootc/discussions)
- [Ubuntu bootc Repository](https://github.com/bootcrew/ubuntu-bootc)

## Learn More

- [Universal Blue Documentation](https://universal-blue.org/)
- [bootc Documentation](https://containers.github.io/bootc/)
- [Ubuntu bootc Project](https://github.com/bootcrew/ubuntu-bootc)

## Security

This template provides security features for production use:
- Optional SBOM generation (Software Bill of Materials) for supply chain transparency
- Optional image signing with cosign for cryptographic verification
- Automated security updates via Renovate
- Build provenance tracking

These security features are disabled by default to allow immediate testing. When you're ready for production, see the "Production Features" section above to enable them.

---

Template based on [Universal Blue finpilot](https://github.com/castrojo/finpilot)

