{
  description = "GNU Taler modules for NixOS";

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" "riscv64-linux" ];
      forSystems = nixpkgs.lib.genAttrs systems;
    in {

      nixosModules = rec {
        default = talerExchange;
        talerExchange = ./nixos-modules/taler-exchange.nix;
      };

      apps = forSystems (system: rec {
        default = example-vm;

        example-vm =
          let
            nixos = nixpkgs.lib.nixosSystem {
              inherit system;
              modules = [ {
                imports = [ self.nixosModules.default ];
                networking.hostName = "taler-example";
                users.users.root.initialHashedPassword = "";
                services.taler-exchange.enable = true;
              } ];
            };
          in {
            type = "app";
            program = "${nixos.config.system.build.vm}/bin/run-taler-example-vm";
          };
      });
        
    };
}
