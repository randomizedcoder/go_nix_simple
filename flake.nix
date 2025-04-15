# flake.nix
{
  description = "A simple Go application packaged with Nix and Docker";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable"; # Or your preferred nixpkgs branch
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};

        # Define the Go application build
        go-nix-simple-app = pkgs.buildGoModule {
          pname = "go-nix-simple";
          version = "0.1.0";

          src = ./.;

          subPackages = [ "cmd/go_nix_simple" ];

          # Needed for Go builds
          #vendorHash = pkgs.lib.fakeSha256; # Use fakeSha256 for initial build, then replace
          #vendorHash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
          vendorHash = "sha256-caiTCIpCDiSspjLd9JI/vr0Mlhud9uNtZ+GtGoTUraU=";
          # Or generate with: nix-prefetch-git --url <your-repo-url> --rev <commit-sha> | jq -r .hash
          # Or if you use go mod vendor:
          # vendorHash = "sha256:<hash-of-vendor-dir>"; # Calculate with nix-hash --type sha256 --base32 ./vendor

          # Add build tags and linker flags for static linking and size reduction
          # buildFlags = [ "-tags=netgo" ];
          ldflags = [
            "-s" "-w" # Strip symbols and debug info
            #"-linkmode=external" "-extldflags=-static" # Force static linking
          ];
          env = {
            CGO_ENABLED = 0;
          };
        };

        # nix-shell -p nix-prefetch-docker
        # nix-prefetch-docker --image-name gcr.io/distroless/static-debian12 --image-tag latest
        distroless-base = pkgs.dockerTools.pullImage {
          imageName = "gcr.io/distroless/static-debian12";
          imageDigest = "sha256:3d0f463de06b7ddff27684ec3bfd0b54a425149d0f8685308b1fdf297b0265e9";
          sha256 = "0ajgz5slpdv42xqrildx850vp4cy6x44yj0hfz53raz3r971ikcf";
          finalImageTag = "latest";
        };

        # Docker image build
        go-nix-simple-image = pkgs.dockerTools.buildLayeredImage {

          name = "randomizedcoder/go-nix-simple";
          tag = "latest";
          # created = "now";

          fromImage = distroless-base;

          contents = [ go-nix-simple-app ];

          config = {

            ExposedPorts = {
              "9108/tcp" = {};
            };
            Cmd = [ "${go-nix-simple-app}/bin/go_nix_simple" ];
            WorkingDir = "/";
            User = "nobody";
          };
        };

      in
      {
        packages.go-nix-simple = go-nix-simple-app;

        packages.docker-image = go-nix-simple-image;

        # `nix build`
        packages.default = self.packages.${system}.docker-image;

        # `nix run`
        apps.default = flake-utils.lib.mkApp {
           drv = go-nix-simple-app;
           exePath = "/bin/go_nix_simple";
        };

        apps.docker-image-tarball = flake-utils.lib.mkApp {
          drv = go-nix-simple-image;
          name = "docker-image-tarball";
        };

      });
}
