# Development Guide

## Project

NixOS flake module for a Windows 11 VM with GPU passthrough (VFIO). See `Goal.md` for architecture and `Plan.md` for implementation phases.

## Build & Test

```bash
# Run all checks (eval tests, XML validation, VM integration tests)
nix flake check

# Build a specific check
nix build .#checks.x86_64-linux.<check-name>

# List available checks
nix flake show
```

## Rules

- **Always run `nix flake check` before committing.** All checks must pass.
- **Kill pending nix builds before starting VM tests.** Nix takes a build lock — a running `nix build` or `nix flake check` will block a new one. Use `pkill -f "nix"` if needed.
- **Use nixpkgs packages when they exist.** Don't create custom fetch derivations for packages already in nixpkgs (e.g., use `pkgs.virtio-win`, not a custom `fetchurl`).
- **Domain XML lives in `resources/win11-domain.xml.in`.** Keep XML in its own file for IDE support. Use `@placeholder@` variables substituted via `pkgs.replaceVars` in `modules/vm-domain.nix`.
- **Don't add `result` or `result-*` symlinks to git.** These are nix build artifacts (covered by `.gitignore`).
- **PRs target `main`.** One PR per phase. Run tests before creating a PR.
- **Assertions over defaults.** The flake asserts host prerequisites (IOMMU, VFIO, libvirt) rather than silently configuring them. See `Goal.md` "Assertions over defaults" section.

## Project Structure

```
modules/          # NixOS module files
  default.nix     # Main module with option definitions
  vfio.nix        # VFIO/IOMMU assertions
  libvirt.nix     # Libvirt assertions
  looking-glass.nix  # Looking Glass config (future)
  vm-domain.nix   # Domain XML generation
resources/        # Templates and resources
  win11-domain.xml.in  # Domain XML template
tests/            # Test files
  eval.nix        # Option evaluation tests
  domain-xml.nix  # XML validation tests
  assertions.nix  # Host assertion tests
  vm-basic.nix    # NixOS VM integration test
```
