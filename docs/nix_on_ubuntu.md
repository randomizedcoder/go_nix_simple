# Instructions for installing Nix on Ubuntu

Taken from:
https://nixos.wiki/wiki/Nix_Installation_Guide#Stable_Nix


## Install Nix

```
sudo install -d -m755 -o $(id -u) -g $(id -g) /nix
curl -L https://nixos.org/nix/install | sh
. /home/das/.nix-profile/etc/profile.d/nix.sh       <--- change username
nix --extra-experimental-features nix-command --extra-experimental-features flakes run "nixpkgs#hello"
```

```
das@chromebox2:~$ sudo install -d -m755 -o $(id -u) -g $(id -g) /nix
das@chromebox2:~$ curl -L https://nixos.org/nix/install | sh
  % Total    % Received % Xferd  Average Speed   Time    Time     Time  Current
                                 Dload  Upload   Total   Spent    Left  Speed
  0     0    0     0    0     0      0      0 --:--:-- --:--:-- --:--:--     0
100  4267  100  4267    0     0   4717      0 --:--:-- --:--:-- --:--:--  4717
downloading Nix 2.28.3 binary tarball for x86_64-linux from 'https://releases.nixos.org/nix/nix-2.28.3/nix-2.28.3-x86_64-linux.tar.xz' to '/tmp/nix-binary-tarball-unpack.G46iRyEPM2'...
  % Total    % Received % Xferd  Average Speed   Time    Time     Time  Current
                                 Dload  Upload   Total   Spent    Left  Speed
100 22.9M  100 22.9M    0     0  38.1M      0 --:--:-- --:--:-- --:--:-- 38.1M
Note: a multi-user installation is possible. See https://nixos.org/manual/nix/stable/installation/installing-binary.html#multi-user-installation
performing a single-user installation of Nix...
copying Nix to /nix/store...

installing 'nix-2.28.3'
building '/nix/store/j8pmzgxnl2zhq2j1fc3j73qrv2i7k48g-user-environment.drv'...
warning: error: unable to download 'https://releases.nixos.org/nixpkgs/nixpkgs-25.05pre792485.3afd19146cac/nixexprs.tar.xz': HTTP error 200 (curl error: Failure when receiving data from the peer); retrying in 309 ms
unpacking 1 channels...
modifying /home/das/.profile...

Installation finished!  To ensure that the necessary environment
variables are set, either log in again, or type

  . /home/das/.nix-profile/etc/profile.d/nix.sh

in your shell.
das@chromebox2:~$ . /home/das/.nix-profile/etc/profile.d/nix.sh
das@chromebox2:~$
```

## Test Nix is working

das@chromebox2:~$ nix --extra-experimental-features nix-command --extra-experimental-features flakes run "nixpkgs#hello"
Hello, world!

## Configure Nix

```
mkdir -p ~/.config/nix
echo "experimental-features = nix-command flakes" > ~/.config/nix/nix.conf
```

```
das@chromebox2:~$ mkdir -p ~/.config/nix
das@chromebox2:~$ echo "experimental-features = nix-command flakes" > ~/.config/nix/nix.conf
das@chromebox2:~$ cat ~/.config/nix/nix.conf
experimental-features = nix-command flakes
```

## clone repo

```
git clone https://github.com/randomizedcoder/go_nix_simple
cd go_nix_simple
```

```
das@chromebox2:~$ git clone https://github.com/randomizedcoder/go_nix_simple
Cloning into 'go_nix_simple'...
remote: Enumerating objects: 415, done.
remote: Counting objects: 100% (415/415), done.
remote: Compressing objects: 100% (242/242), done.
remote: Total 415 (delta 228), reused 315 (delta 141), pack-reused 0 (from 0)
Receiving objects: 100% (415/415), 33.36 MiB | 16.16 MiB/s, done.
Resolving deltas: 100% (228/228), done.
das@chromebox2:~$ cd go_nix_simple/
das@chromebox2:~/go_nix_simple$
```

## nix develop

Enter the development shell.

This will create the new development shell and enter it.  This will be slow the first time, because it is using the unstable branch (which is pinned into the flake.lock file).

```
nix develop
```


```
das@chromebox2:~/go_nix_simple$ nix develop
Entered Nix development shell for go-nix-simple.
(nix-dev) ~/go_nix_simple$
```

If ~/.config/nix/nix.conf was not updated:
```
das@chromebox2:~/go_nix_simple$ nix --extra-experimental-features nix-command --extra-experimental-features flakes develop
warning: download buffer is full; consider increasing the 'download-buffer-size' setting
Entered Nix development shell for go-nix-simple.
(nix-dev) ~/go_nix_simple$
```

## Build the oci containers using bazel

This will use bazel to build the go_nix_simple go binary into a container based on scratch and distroless.

```
make bazel-build-all
```

```
(nix-dev) ~/go_nix_simple$ make bazel-build-all
for platform in //platforms:linux_amd64; do \
        bazel build --platforms=$platform \
                //cmd/go_nix_simple:image_bazel_distroless_tarball \
                --define REPO_PREFIX=docker.io/randomizedcoder \
                --define VERSION=latest; \
done
Extracting Bazel installation...
Starting local Bazel server and connecting to it...
WARNING: /home/das/go_nix_simple/MODULE.bazel:48:20: The module extension oci defined in @rules_oci//oci:extensions.bzl reported incorrect imports of repositories via use_repo():

Not imported, but reported as direct dependencies by the extension (may cause the build to fail):
    distroless_base_amd64_linux_amd64

Fix the use_repo calls by running 'bazel mod tidy'.
INFO: Analyzed target //cmd/go_nix_simple:image_bazel_distroless_tarball (257 packages loaded, 15482 targets configured).
INFO: Found 1 target...
Target //cmd/go_nix_simple:image_bazel_distroless_tarball up-to-date:
  bazel-bin/cmd/go_nix_simple/push_image_bazel_distroless_tarball.sh
INFO: Elapsed time: 409.948s, Critical Path: 211.10s
INFO: 159 processes: 21 internal, 1 local, 137 processwrapper-sandbox.
INFO: Build completed successfully, 159 total actions
for platform in //platforms:linux_amd64; do \
        bazel build --platforms=$platform \
                //cmd/go_nix_simple:image_bazel_scratch_tarball \
                --define REPO_PREFIX=docker.io/randomizedcoder \
                --define VERSION=latest; \
done
INFO: Analyzed target //cmd/go_nix_simple:image_bazel_scratch_tarball (0 packages loaded, 7 targets configured).
INFO: Found 1 target...
Target //cmd/go_nix_simple:image_bazel_scratch_tarball up-to-date:
  bazel-bin/cmd/go_nix_simple/push_image_bazel_scratch_tarball.sh
INFO: Elapsed time: 4.111s, Critical Path: 2.63s
INFO: 15 processes: 10 internal, 5 processwrapper-sandbox.
INFO: Build completed successfully, 15 total actions
(nix-dev) ~/go_nix_simple$
```