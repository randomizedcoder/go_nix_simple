#
# https://github.com/randomizedcoder/go_nix_simple
#
# flake.nix
#
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
          config = {
            allowUnfree = true;
          };
        };

        appVersion = builtins.readFile ./VERSION;

        # Common ldflags for Go builds
        commonLdflags = [ "-s" "-w" "-X main.version=${appVersion}" "-X main.commit=nix-build" "-X main.date=unknown" ];
        # Common buildFlags for Go builds
        commonBuildFlags = [ "-tags=netgo,osusergo" "-trimpath" ];

        # --- Base Binary Derivations ---

        # Binary built using Nixpkgs buildGoModule
        binaryNixBuildGoModule = pkgs.buildGoModule { # Renamed from binaryNixDefault
          pname = "go-nix-simple-buildgomodule"; # Adjusted pname
          version = appVersion;
          src = ./.;
          subPackages = [ "cmd/go_nix_simple" ];
          # Ensure this hash is updated when go.mod/go.sum changes
          # Run: nix build .#binary-nix-buildgomodule --rebuild
          #vendorHash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
          vendorHash = "sha256-iMUa+OE/Ecb3TDw4PmvRfujo++T/r4g/pW0ZT63zIC4=";
          ldflags = commonLdflags;
          buildFlags = commonBuildFlags;
          env = { CGO_ENABLED = 0; };
          # postInstall = ''
          #   mv $out/bin/go-nix-simple-buildgomodule $out/bin/go_nix_simple
          # '';
        };

        # Binary built using gomod2nix buildGoApplication
        binaryNixGomod2nix = pkgs.buildGoApplication {
          pname = "go-nix-simple-gomod2nix";
          version = appVersion;
          modules = ./gomod2nix.toml;
          src = ./.;
          ldflags = commonLdflags;
          buildFlags = commonBuildFlags;
          #env = { CGO_ENABLED = 0; };
          CGO_ENABLED = 0;
          # postInstall = ''
          #   mv $out/bin/go-nix-simple-gomod2nix $out/bin/go_nix_simple
          # '';
        };

        # --- UPX Packed Binary Derivations ---

        # UPX version of the buildGoModule binary
        binaryNixBuildGoModuleUpx = pkgs.runCommand "go-nix-simple-buildgomodule-upx" { # Renamed
          nativeBuildInputs = [ pkgs.upx ];
          src = binaryNixBuildGoModule; # Depend on the renamed binary derivation
        } ''
          mkdir -p $out/bin
          local orig_bin="$src/bin/go_nix_simple"
          echo "Original size ($(basename $orig_bin)): $(ls -lh $orig_bin | awk '{print $5}')"
          upx --best --lzma -o $out/bin/go_nix_simple "$orig_bin"
          echo "Compressed size ($(basename $out/bin/go_nix_simple)): $(ls -lh $out/bin/go_nix_simple | awk '{print $5}')"
          chmod +x $out/bin/go_nix_simple
        '';

        # UPX version of the gomod2nix binary
        binaryNixGomod2nixUpx = pkgs.runCommand "go-nix-simple-gomod2nix-upx" {
          nativeBuildInputs = [ pkgs.upx ];
          src = binaryNixGomod2nix;
        } ''
          mkdir -p $out/bin
          local orig_bin="$src/bin/go_nix_simple" # Assumes postInstall worked
          echo "Original size ($(basename $orig_bin)): $(ls -lh $orig_bin | awk '{print $5}')"
          upx --best --lzma -o $out/bin/go_nix_simple "$orig_bin"
          echo "Compressed size ($(basename $out/bin/go_nix_simple)): $(ls -lh $out/bin/go_nix_simple | awk '{print $5}')"
          chmod +x $out/bin/go_nix_simple
        '';


        # --- Common Image Components ---

        etcFiles = pkgs.runCommand "etc-files" {} ''
          mkdir -p $out/etc
          echo 'nogroup:x:65534:' > $out/etc/group
          echo 'nobody:x:65534:65534:Nobody:/:/sbin/nologin' > $out/etc/passwd
        '';

        versionFilePkg = pkgs.runCommand "version-file" {} ''
          mkdir -p $out
          cp ${./VERSION} $out/VERSION
        '';

        distrolessBase = pkgs.dockerTools.pullImage {
          imageName = "gcr.io/distroless/static-debian12";
          imageDigest = "sha256:3d0f463de06b7ddff27684ec3bfd0b54a425149d0f8685308b1fdf297b0265e9";
          sha256 = "0ajgz5slpdv42xqrildx850vp4cy6x44yj0hfz53raz3r971ikcf";
          finalImageTag = "latest";
        };

        # Helper function to build layered images
        buildImage = { name, tag ? "latest", baseImage ? null, binaryPkg, extraContents ? [] }:
          pkgs.dockerTools.buildLayeredImage {
            inherit name tag;
            fromImage = baseImage;
            contents = [ binaryPkg versionFilePkg etcFiles ] ++ extraContents;
            config = {
              User = "nobody";
              WorkingDir = "/";
              ExposedPorts = { "9108/tcp" = {}; };
              Cmd = [ "${binaryPkg}/bin/go_nix_simple" ];
            };
          };

        # --- Image Derivations (All Combinations) ---

        # Distroless + BuildGoModule + NoUPX
        imageNixDistrolessBuildGoModuleNoupx = buildImage { # Renamed
          name = "randomizedcoder/nix-go-nix-simple-distroless-buildgomodule-noupx"; # Renamed
          baseImage = distrolessBase;
          binaryPkg = binaryNixBuildGoModule; # Use renamed binary
        };

        # Distroless + BuildGoModule + UPX
        imageNixDistrolessBuildGoModuleUpx = buildImage { # Renamed
          name = "randomizedcoder/nix-go-nix-simple-distroless-buildgomodule-upx"; # Renamed
          baseImage = distrolessBase;
          binaryPkg = binaryNixBuildGoModuleUpx; # Use renamed binary
        };

        # Distroless + Gomod2nix + NoUPX
        imageNixDistrolessGomod2nixNoupx = buildImage {
          name = "randomizedcoder/nix-go-nix-simple-distroless-gomod2nix-noupx";
          baseImage = distrolessBase;
          binaryPkg = binaryNixGomod2nix;
        };

        # Distroless + Gomod2nix + UPX
        imageNixDistrolessGomod2nixUpx = buildImage {
          name = "randomizedcoder/nix-go-nix-simple-distroless-gomod2nix-upx";
          baseImage = distrolessBase;
          binaryPkg = binaryNixGomod2nixUpx;
        };

        # Scratch + BuildGoModule + NoUPX
        imageNixScratchBuildGoModuleNoupx = buildImage { # Renamed
          name = "randomizedcoder/nix-go-nix-simple-scratch-buildgomodule-noupx"; # Renamed
          binaryPkg = binaryNixBuildGoModule; # Use renamed binary
        };

        # Scratch + BuildGoModule + UPX
        imageNixScratchBuildGoModuleUpx = buildImage { # Renamed
          name = "randomizedcoder/nix-go-nix-simple-scratch-buildgomodule-upx"; # Renamed
          binaryPkg = binaryNixBuildGoModuleUpx; # Use renamed binary
        };

        # Scratch + Gomod2nix + NoUPX
        imageNixScratchGomod2nixNoupx = buildImage {
          name = "randomizedcoder/nix-go-nix-simple-scratch-gomod2nix-noupx";
          binaryPkg = binaryNixGomod2nix;
        };

        # Scratch + Gomod2nix + UPX
        imageNixScratchGomod2nixUpx = buildImage {
          name = "randomizedcoder/nix-go-nix-simple-scratch-gomod2nix-upx";
          binaryPkg = binaryNixGomod2nixUpx;
        };

        # --- Utility Images (Example: Athens) ---
        athensNixImage = pkgs.dockerTools.buildLayeredImage {
          name = "randomizedcoder/athens-nix";
          tag = "latest";
          fromImage = distrolessBase;
          contents = [ pkgs.athens etcFiles ];
          config = {
            User = "nobody";
            WorkingDir = "/data";
            ExposedPorts = { "8888/tcp" = {}; };
            Volumes = { "/data/athens" = {}; };
            Env = [
              "ATHENS_HOST=0.0.0.0"
              "ATHENS_PORT=8888"
              "ATHENS_STORAGE_TYPE=disk"
              "ATHENS_DISK_STORAGE_ROOT=/data/athens"
              "ATHENS_LOG_LEVEL=info"
            ];
            Cmd = [ "${pkgs.athens}/bin/athens" ];
          };
        };

      in
      {
        # --- Consistent Package Naming ---
        packages = {
          # Binaries
          binary-nix-buildgomodule = binaryNixBuildGoModule; # Renamed key
          binary-nix-buildgomodule-upx = binaryNixBuildGoModuleUpx; # Renamed key
          binary-nix-gomod2nix = binaryNixGomod2nix;
          binary-nix-gomod2nix-upx = binaryNixGomod2nixUpx;

          # Images (All 8 combinations)
          image-nix-distroless-buildgomodule-noupx = imageNixDistrolessBuildGoModuleNoupx; # Renamed key
          image-nix-distroless-buildgomodule-upx = imageNixDistrolessBuildGoModuleUpx; # Renamed key
          image-nix-distroless-gomod2nix-noupx = imageNixDistrolessGomod2nixNoupx;
          image-nix-distroless-gomod2nix-upx = imageNixDistrolessGomod2nixUpx;
          image-nix-scratch-buildgomodule-noupx = imageNixScratchBuildGoModuleNoupx; # Renamed key
          image-nix-scratch-buildgomodule-upx = imageNixScratchBuildGoModuleUpx; # Renamed key
          image-nix-scratch-gomod2nix-noupx = imageNixScratchGomod2nixNoupx;
          image-nix-scratch-gomod2nix-upx = imageNixScratchGomod2nixUpx;

          # Utility Images
          athens-nix-image = athensNixImage;

          # Default package for `nix build`
          default = self.packages.${system}.image-nix-distroless-buildgomodule-noupx; # Updated default
        };

        # --- Apps ---
        apps = {
          # Default app for `nix run`
          default = flake-utils.lib.mkApp {
            drv = self.packages.${system}.binary-nix-buildgomodule;
            # Explicitly tell mkApp where the executable is
            exePath = "/bin/go_nix_simple";
          };
          gomod2nix = flake-utils.lib.mkApp {
            drv = self.packages.${system}.binary-nix-gomod2nix;
            # Also specify exePath here for consistency, since postInstall renames it
            exePath = "/bin/go_nix_simple";
          };

          # Apps to output image tarballs (useful for loading into Docker)
          # Update keys to match package names
          image-distroless-buildgomodule-noupx-tarball = flake-utils.lib.mkApp { drv = self.packages.${system}.image-nix-distroless-buildgomodule-noupx; };
          image-distroless-buildgomodule-upx-tarball = flake-utils.lib.mkApp { drv = self.packages.${system}.image-nix-distroless-buildgomodule-upx; };
          image-distroless-gomod2nix-noupx-tarball = flake-utils.lib.mkApp { drv = self.packages.${system}.image-nix-distroless-gomod2nix-noupx; };
          image-distroless-gomod2nix-upx-tarball = flake-utils.lib.mkApp { drv = self.packages.${system}.image-nix-distroless-gomod2nix-upx; };
          image-scratch-buildgomodule-noupx-tarball = flake-utils.lib.mkApp { drv = self.packages.${system}.image-nix-scratch-buildgomodule-noupx; };
          image-scratch-buildgomodule-upx-tarball = flake-utils.lib.mkApp { drv = self.packages.${system}.image-nix-scratch-buildgomodule-upx; };
          image-scratch-gomod2nix-noupx-tarball = flake-utils.lib.mkApp { drv = self.packages.${system}.image-nix-scratch-gomod2nix-noupx; };
          image-scratch-gomod2nix-upx-tarball = flake-utils.lib.mkApp { drv = self.packages.${system}.image-nix-scratch-gomod2nix-upx; };
        };

        # --- Dev Shell ---
        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            go
            gopls
            gotools
            golint
            golangci-lint
            go-tools
            golangci-lint-langserver
            gomod2nix.packages.${system}.default
            #gomod2nix
            upx
            # https://github.com/bazelbuild/bazel/tags
            # https://github.com/NixOS/nixpkgs/blob/nixos-unstable/pkgs/development/tools/build-managers/bazel/bazel_7/default.nix#L524
            bazel_7
            # https://github.com/bazel-contrib/bazel-gazelle/tags
            # https://github.com/NixOS/nixpkgs/blob/nixos-unstable/pkgs/by-name/ba/bazel-gazelle/package.nix#L26
            bazel-gazelle
            bazel-buildtools
            bazelisk
            #
            curl
            jq
            #
            dive
            #
            code-cursor
          ];
          shellHook = ''
            export PS1='(nix-dev) \w\$ '
            echo "Entered Nix development shell for go-nix-simple."
          '';

          # You might have other shell attributes here
          # Example: GOPATH = "${pkgs.buildGoModule}/share/go";
        };
      });
}
# end
