# flake.nix
{
  description = "A simple Go application packaged with Nix and Docker";

  inputs = {
    #nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";

    gomod2nix = {
      url = "github:tweag/gomod2nix";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
    };

  };

  outputs = { self, nixpkgs, flake-utils, gomod2nix }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [ gomod2nix.overlays.default ];
        };
        #pkgs = nixpkgs.legacyPackages.${system};

        appVersion = builtins.readFile ./VERSION;

        etc-group = pkgs.runCommand "etc-group" {} ''
          mkdir -p $out/etc
          echo 'nogroup:x:65534:' > $out/etc/group
        '';
        etc-passwd = pkgs.runCommand "etc-passwd" {} ''
          mkdir -p $out/etc
          # Format: username:password:UID:GID:GECOS:home_dir:shell
          echo 'nobody:x:65534:65534:Nobody:/:/sbin/nologin' > $out/etc/passwd
        '';

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
          ldflags = [ "-s" "-w" "-X main.version=${appVersion}" "-X main.commit=nix-build" "-X main.date=unknown" ];
            #"-linkmode=external" "-extldflags=-static" # Force static linking
          buildFlags = [ "-tags=netgo,osusergo" "-trimpath" ];
          env = { CGO_ENABLED = 0; };
            # Turns out that you can't use GOPROXY :(
            # export GOPROXY="http://localhost:8888"
            #GOPROXY = "http://localhost:8888";
            #GOPROXY = "http://10.88.88.88:8888";
            #GOPROXY = "http://127.0.0.1:3000";  #ATHENS_PORT=3000
          # preBuild = ''
          #   GOPROXY="http://localhost:8888,direct"
          # '';
          # https://discourse.nixos.org/t/rethink-goproxy/23534/10
        };

        # UPX Compression!
        go-nix-simple-app-upx = pkgs.runCommand "go-nix-simple-upx" {
            nativeBuildInputs = [ pkgs.upx ];
            originalBinary = go-nix-simple-app;
          } ''
            # Create the output structure (mirroring buildGoModule)
            mkdir -p $out/bin

            # Copy the original binary to a temporary location within the build sandbox
            cp $originalBinary/bin/go_nix_simple ./go_nix_simple_orig

            echo "Original size:"
            ls -lh ./go_nix_simple_orig

            # Run UPX on the copied binary, outputting to the final destination
            upx --best --lzma -o $out/bin/go_nix_simple ./go_nix_simple_orig

            echo "Compressed size:"
            ls -lh $out/bin/go_nix_simple

            # Ensure the compressed binary is executable
            chmod +x $out/bin/go_nix_simple
          '';

        go-nix-simple-gomod2nix = pkgs.buildGoApplication {
          pname = "go-nix-simple-gomod2nix";
          version = "0.1.1";
          modules = ./gomod2nix.toml;
          src = ./.;
          ldflags = [ "-s" "-w" "-X main.version=${appVersion}" "-X main.commit=nix-build" "-X main.date=unknown" ];
          buildFlags = [ "-tags=netgo,osusergo" "-trimpath" ];
          CGO_ENABLED = 0;
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
          name = "randomizedcoder/nix-go-nix-simple-distroless";
          tag = "latest";
          # created = "now";
          fromImage = distroless-base;
          contents = [ go-nix-simple-app version-file-pkg etc-group etc-passwd ];
          config = {
            ExposedPorts = { "9108/tcp" = {}; };
            Cmd = [ "${go-nix-simple-app}/bin/go_nix_simple" ];
            WorkingDir = "/";
            User = "nobody";
          };
        };

        go-nix-simple-image-scratch = pkgs.dockerTools.buildLayeredImage {
          name = "randomizedcoder/nix-go-nix-simple-scratch";
          tag = "latest";
          # created = "now";
          # fromImage defaults to null, which is equivalent to SCRATCH
          #fromImage = distroless-base;
          contents = [ go-nix-simple-app version-file-pkg etc-group etc-passwd ];
          config = {
            ExposedPorts = { "9108/tcp" = {}; };
            Cmd = [ "${go-nix-simple-app}/bin/go_nix_simple" ];
            WorkingDir = "/";
            User = "nobody";
          };
        };

        go-nix-simple-image-upx = pkgs.dockerTools.buildLayeredImage {
          name = "randomizedcoder/nix-go-nix-simple-scratch-upx";
          tag = "latest";
          #fromImage = distroless-base;
          contents = [ go-nix-simple-app-upx version-file-pkg etc-group etc-passwd ];
          config = {
            ExposedPorts = { "9108/tcp" = {}; };
            Cmd = [ "${go-nix-simple-app-upx}/bin/go_nix_simple" ];
            WorkingDir = "/";
            User = "nobody";
          };
        };

        go-nix-simple-gomod2nix-image = pkgs.dockerTools.buildLayeredImage {
          name = "randomizedcoder/gomod2nix-go-nix-simple-scratch";
          tag = "latest";
          # created = "now";
          #fromImage = distroless-base;
          contents = [ go-nix-simple-gomod2nix version-file-pkg etc-group etc-passwd ];
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
          contents = [ pkgs.athens etc-group etc-passwd ];
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
            WorkingDir = "/data";
            Volumes = { "/data/athens" = {}; };
            User = "nobody";
          };
        };

      in
      {
        packages.go-nix-simple = go-nix-simple-app;
        packages.go-nix-simple-upx = go-nix-simple-app-upx;
        packages.go-nix-simple-gomod2nix = go-nix-simple-gomod2nix;
        packages.docker-image-scratch = go-nix-simple-image-scratch;
        packages.docker-image = go-nix-simple-image;
        packages.docker-image-upx = go-nix-simple-image-upx;
        packages.docker-image-gomod2nix = go-nix-simple-gomod2nix-image;
        packages.athens-nix-image = athens-nix-image;

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
        apps.docker-image-upx-tarball = flake-utils.lib.mkApp {
          drv = go-nix-simple-image-upx;
          name = "docker-image-upx-tarball";
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