{
  description = "Crostini NixOS + Home Manager (chronos) with generators, nixGL, nix-community overlays";

  inputs = {
    # Core nixpkgs
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    # Generators (LXC, ISO, etc.)
    nixos-generators = {
      url = "github:nix-community/nixos-generators";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Home Manager
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # GPU wrapper for GL/Vulkan: works well under Crostini's virtGL
    nixgl = {
      url = "github:guibou/nixGL";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # nix-community overlays we may want
    nix-index-database = {
      url = "github:nix-community/nix-index-database";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixpkgs-wayland = {
      url = "github:nix-community/nixpkgs-wayland";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, nixos-generators, home-manager, nixgl, nix-index-database, nixpkgs-wayland, ... }@inputs:
    let
      specialArgs = { inherit inputs; };

      defaultSystem = "aarch64-linux";

      overlays = [
        nixgl.overlays.default
        nixpkgs-wayland.overlays.default
      ];

      forAllSystems = f:
        nixpkgs.lib.genAttrs [ "x86_64-linux" "aarch64-linux" ] (system: f system);
    in
    {
      ########################
      ## Image build outputs ##
      ########################
      packages = forAllSystems (system:
        let
          pkgs = import nixpkgs {
            inherit system overlays;
            config.allowUnfree = true;
          };

          gen = args: nixos-generators.nixosGenerate ({
            inherit system specialArgs;
            modules = [ ./configuration.nix self.nixosModules.default ];
          } // args);
        in rec {
          lxc = gen { format = "lxc"; };
          lxc-metadata = gen { format = "lxc-metadata"; };

          # Convenience attr that symlinks both tarballs
          default = pkgs.stdenv.mkDerivation {
            name = "lxc-image-and-metadata";
            dontUnpack = true;
            installPhase = ''
              mkdir -p $out
              ln -s ${lxc-metadata}/tarball/*.tar.xz $out/metadata.tar.xz
              ln -s ${lxc}/tarball/*.tar.xz $out/image.tar.xz
            '';
          };
        });

      ###################################
      ## NixOS system (inside container) ##
      ###################################
      nixosConfigurations.seagull = nixpkgs.lib.nixosSystem {
        system = defaultSystem;
        inherit specialArgs;

        modules = [
          ./configuration.nix
          self.nixosModules.default

          # Home Manager, wired to our home.nix
          home-manager.nixosModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;

            home-manager.users.chronos = import ./home.nix;

            nixpkgs = {
              overlays = overlays;
              config.allowUnfree = true;
            };
          }
        ];
      };

      ##################################
      ## Standalone Home Manager usage ##
      ##################################
      homeConfigurations."chronos" = home-manager.lib.homeManagerConfiguration {
        pkgs = import nixpkgs {
          system = defaultSystem;
          overlays = overlays;
          config.allowUnfree = true;
        };
        modules = [ ./home.nix ];
      };

      ################
      ## NixOS module ##
      ################
      nixosModules = rec {
        nixos-crostini = ./crostini.nix;
        default = nixos-crostini;
      };

      ################
      ## Flake template (optional) ##
      ################
      templates.default = {
        path = self;
        description = "NixOS+HM Crostini with nixGL and generators";
      };
    };
}
