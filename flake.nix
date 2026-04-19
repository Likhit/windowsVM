{
  description = "Windows 11 VM with GPU passthrough via VFIO for NixOS";

  inputs = {
    # Used only for running checks/tests. The module itself uses the
    # consuming NixOS system's nixpkgs at evaluation time.
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
  };

  outputs = { self, nixpkgs }: let
    system = "x86_64-linux";
    pkgs = nixpkgs.legacyPackages.${system};
  in {
    nixosModules.default = import ./modules/default.nix;

    checks.${system} =
      (import ./tests/eval.nix {
        inherit pkgs;
        module = self.nixosModules.default;
      }) //
      (import ./tests/domain-xml.nix {
        inherit pkgs;
        module = self.nixosModules.default;
      }) //
      (import ./tests/assertions.nix {
        inherit pkgs;
        module = self.nixosModules.default;
      }) //
      {
        vm-basic = import ./tests/vm-basic.nix {
          inherit pkgs;
          module = self.nixosModules.default;
        };
      };
  };
}
