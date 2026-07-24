{
  description = "AppHost";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

    disko = {
      url    = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    lanzaboote = {
      url    = "github:nix-community/lanzaboote";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, disko, lanzaboote, ... }:
  let
    hwConfig = ./nixos/hardware-configuration.nix;
  in
  {
    nixosConfigurations.apphost = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";

      modules = [
        disko.nixosModules.disko
        lanzaboote.nixosModules.lanzaboote
        ./nixos/disko.nix
        ./nixos/configuration.nix

      ] ++ nixpkgs.lib.optionals (builtins.pathExists hwConfig) [ hwConfig ];
    };
  };
}
