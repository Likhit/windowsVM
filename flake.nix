{
  description = "Windows 11 VM with GPU passthrough via VFIO for NixOS";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }: let
    system = "x86_64-linux";
    pkgs = nixpkgs.legacyPackages.${system};
  in {
    nixosModules.default = import ./modules/default.nix;

    checks.${system} = import ./tests/eval.nix {
      inherit pkgs;
      module = self.nixosModules.default;
    };
  };
}
