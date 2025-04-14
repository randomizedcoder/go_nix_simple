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
          version = "0.1.0"; # You can manage the version here

          # Assuming your flake.nix is at the root of go_nix_simple
          # and your go code is in ./cmd/go_nix_simple/
          src = ./.;

          # Tell Go where the main package is
          subPackages = [ "cmd/go_nix_simple" ];

          # Needed for Go builds
          vendorHash = pkgs.lib.fakeSha256; # Use fakeSha256 for initial build, then replace
          # Or generate with: nix-prefetch-git --url <your-repo-url> --rev <commit-sha> | jq -r .hash
          # Or if you use go mod vendor:
          # vendorHash = "sha256:<hash-of-vendor-dir>"; # Calculate with nix-hash --type sha256 --base32 ./vendor

          # Optional: Add build tags or linker flags if needed
          # buildFlags = [ "-tags=netgo" ];
          # ldflags = [ "-s" "-w" ]; # Example: strip debugging info
        };

        # Define the Docker image build
        go-nix-simple-image = pkgs.dockerTools.buildLayeredImage {
          name = "go-nix-simple";
          tag = "latest"; # Or use the version from go-nix-simple-app

          # Use a minimal base image (distroless static)
          # Ensure your Go binary is statically linked for this to work best.
          # Add ldflags = [ "-linkmode=external" "-extldflags=-static" ]; to buildGoModule if needed.
          # Or use a slightly larger base like pkgs.dockerTools.busyboxImage
          fromImage = pkgs.dockerTools.distroless.static; # Minimal base

          # Contents of the image: just our Go binary
          contents = [ go-nix-simple-app ];

          # Configure how the container runs
          config = {
            # Expose the Prometheus port
            ExposedPorts = {
              "9108/tcp" = {};
            };
            # Command to run when the container starts
            # This assumes the binary is placed in /bin/go_nix_simple by buildGoModule
            Cmd = [ "${go-nix-simple-app}/bin/go_nix_simple" ];
            WorkingDir = "/";
            # You might want to set a non-root user for better security
            # User = "nobody";
          };
        };

      in
      {
        # The Go binary package
        packages.go-nix-simple = go-nix-simple-app;

        # The Docker image package
        packages.docker-image = go-nix-simple-image;

        # Default package when running `nix build`
        packages.default = self.packages.${system}.docker-image;

        # Allow running the app directly using `nix run`
        apps.default = flake-utils.lib.mkApp {
           drv = go-nix-simple-app;
           exePath = "/bin/go_nix_simple"; # Adjust if the binary path is different
        };

        # You can also provide the docker image tarball via apps
        apps.docker-image-tarball = flake-utils.lib.mkApp {
          drv = go-nix-simple-image;
          # This doesn't "run" anything, but `nix run .#docker-image-tarball`
          # will build the image and place the tarball in ./result
          # You can then load it with `docker load < result`
          name = "docker-image-tarball";
        };

      });
}
