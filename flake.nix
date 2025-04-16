# flake.nix
{
  description = "A simple Go application packaged with Nix and Docker";

  inputs = {
    #nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    utils.url = "github:numtide/flake-utils";

    gomod2nix = {
      url = "github:tweag/gomod2nix";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.utils.follows = "utils";
    };

  };

  outputs = { self, nixpkgs, utils, gomod2nix }:
    utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [ gomod2nix.overlays.default ];
        };
        #pkgs = nixpkgs.legacyPackages.${system};

        # Define the Go application build
        # https://github.com/NixOS/nixpkgs/blob/master/pkgs/build-support/go/module.nix
        go-nix-simple-app = pkgs.buildGoModule {

          pname = "go-nix-simple";
          version = "0.1.1";

          src = ./.;

          subPackages = [ "cmd/go_nix_simple" ];

          # sha256-AAAA is to allow nix to calculate the NAR hash
          #vendorHash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
          vendorHash = "sha256-HE30rYfraiQVQrYDgZfRrEU1eoVwtlrr88Uvz/rupx8=";
          #vendorHash = "sha256-caiTCIpCDiSspjLd9JI/vr0Mlhud9uNtZ+GtGoTUraU=";
          # Or generate with: nix-prefetch-git --url <your-repo-url> --rev <commit-sha> | jq -r .hash
          # Or if you use go mod vendor:
          # vendorHash = "sha256:<hash-of-vendor-dir>"; # Calculate with nix-hash --type sha256 --base32 ./vendor

          # https://nixos.org/manual/nixpkgs/stable/#var-go-ldflags
          # Add build tags and linker flags for static linking and size reduction
          # buildFlags = [ "-tags=netgo" ];
          ldflags = [
            "-s" "-w" # Strip symbols and debug info
            #"-linkmode=external" "-extldflags=-static" # Force static linking
          ];
          env = {
            CGO_ENABLED = 0;
            # Turns out that you can't use GOPROXY :(
            # export GOPROXY="http://localhost:8888"
            #GOPROXY = "http://localhost:8888";
            #GOPROXY = "http://10.88.88.88:8888";
            #GOPROXY = "http://127.0.0.1:3000";  #ATHENS_PORT=3000
          };
          # preBuild = ''
          #   GOPROXY="http://localhost:8888,direct"
          # '';
          # https://discourse.nixos.org/t/rethink-goproxy/23534/10
        };

        go-nix-simple-gomod2nix = pkgs.buildGoApplication {
          pname = "go-nix-simple-gomod2nix";
          version = "0.1.1";
          src = ./.;
          modules = ./gomod2nix.toml;
        };
        # https://github.com/nix-community/gomod2nix/blob/master/docs/nix-reference.md#buildgoapplication

        version-file-pkg = pkgs.runCommand "version-file" {} ''
          mkdir -p $out
          cp ${./VERSION} $out/VERSION
        '';

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

          contents = [
            go-nix-simple-app
            version-file-pkg
          ];

          config = {

            ExposedPorts = {
              "9108/tcp" = {};
            };
            Cmd = [ "${go-nix-simple-app}/bin/go_nix_simple" ];
            WorkingDir = "/";
            User = "nobody";
          };
        };

        go-nix-simple-gomod2nix-image = pkgs.dockerTools.buildLayeredImage {

          name = "randomizedcoder/go-nix-simple-gomod2nix";
          tag = "latest";
          # created = "now";

          fromImage = distroless-base;

          contents = [
            go-nix-simple-gomod2nix
            version-file-pkg
          ];

          config = {

            ExposedPorts = {
              "9108/tcp" = {};
            };
            Cmd = [ "${go-nix-simple-app}/bin/go_nix_simple" ];
            WorkingDir = "/";
            User = "nobody";
          };
        };

        athens-nix-image = pkgs.dockerTools.buildLayeredImage {

          name = "randomizedcoder/athens-nix";
          tag = "latest";

          fromImage = distroless-base;

          contents = [ pkgs.athens ];

          config = {
            ExposedPorts = { "8888/tcp" = {}; };

            Cmd = [ "${pkgs.athens}/bin/athens" ];

            Env = [
              # Listen on all interfaces inside the container on port 3000
              "ATHENS_HOST=0.0.0.0"
              "ATHENS_PORT=8888"
              # Use disk storage within the container
              "ATHENS_STORAGE_TYPE=disk"
              # Define a path for the storage (will be created if it doesn't exist)
              "ATHENS_DISK_STORAGE_ROOT=/data/athens"
              # Optional: Set log level
              "ATHENS_LOG_LEVEL=info"
            ];

            # Set working directory (optional, but good practice)
            WorkingDir = "/data";

            # Define a volume for persistent storage (optional but recommended)
            # This tells Docker users that /data/athens is intended for storage
            Volumes = { "/data/athens" = {}; };

            # Consider running as a non-root user for better security
            # User = "nobody"; # Requires /data to be writable by 'nobody'
          };
        };

      in
      {
        packages.go-nix-simple = go-nix-simple-app;

        packages.go-nix-simple-gomod2nix = go-nix-simple-gomod2nix;

        packages.docker-image = go-nix-simple-image;

        packages.docker-image-gomod2nix = go-nix-simple-gomod2nix-image;

        # `nix build`
        packages.default = self.packages.${system}.docker-image;

        packages.athens-nix-image = athens-nix-image;

        # `nix run`
        apps.default = utils.lib.mkApp {
           drv = go-nix-simple-app;
           exePath = "/bin/go_nix_simple";
        };

        apps.docker-image-tarball = utils.lib.mkApp {
          drv = go-nix-simple-image;
          name = "docker-image-tarball";
        };

        # `nix develop`
        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            go
            gopls
            gotools
            go-tools
            gomod2nix.packages.${system}.default
          ];
        };



      });
}
# end