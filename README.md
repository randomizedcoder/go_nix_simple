# go_nix_simple

This is an example repo that shows building a simple go program, and then building small docker images using:
- Nix with standard buildGoModule ( no sharing of dependencies between packages that depend on the same Go module )
- Docker build with docker caching
- Docker build with athens GO_PROXY caching
- Nix buildGoApplication ( gomod2nix )

## Summary

| Build Method                          | Build Time | Build Time Cached | Image Size  |
| :------------------------------------ | :--------- | :---------------- | :---------- |
| Nix buildGoModule                     | 20699 ms   | 3548 ms           | 12.8 MB     |
| Docker built docker cache             | 9319 ms    | 1524 ms           | 14.3 MB     |  <--- docker cache is fast!
| Docker built athens cache             | 9319 ms    | 8107 ms           | 14.3 MB     |
| Nix buildGoApplication ( gomod2nix )  | 23296 ms   | 3567 ms           | 54.6 MB     |  <--- image is large! :(


Please see the [Makefile](./Makefile) for how to run this

## make

```
make deploy_athens   <--- Start Athens proxy cache for go
make
```

### make when NOT cached
```
[das@t:~/Downloads/go_nix_simple]$ make
[] Starting nix_build_docker...
warning: Git tree '/home/das/Downloads/go_nix_simple' is dirty
warning: input 'gomod2nix' has an override for a non-existent input 'utils'
[] Finished nix_build_docker. Duration: 20699 ms.
[] Starting nix_build_docker_load...
ee3c3c94f535: Loading layer [==================================================>]  8.274MB/8.274MB
0c3944774c1e: Loading layer [==================================================>]  10.24kB/10.24kB
71b5100f321d: Loading layer [==================================================>]  10.24kB/10.24kB
The image randomizedcoder/go-nix-simple:latest already exists, renaming the old one with ID sha256:8cd4c7e3200ad84315f4146f46bd35bdb05ee4c833f71fe2d30c3a9385697745 to empty string
Loaded image: randomizedcoder/go-nix-simple:latest
[] Finished nix_build_docker_load. Duration: 206 ms.
[] Starting builddocker_go-nix-simple-distroless...
================================
Make builddocker_go_nix_simple randomizedcoder/go-nix-simple-distroless:1.0.0
[+] Building 9.2s (15/15) FINISHED                                                                                                                                              docker:default
 => [internal] load build definition from Containerfile                                                                                                                                   0.0s
 => => transferring dockerfile: 1.61kB                                                                                                                                                    0.0s
 => [internal] load metadata for gcr.io/distroless/static-debian12:latest                                                                                                                 0.5s
 => [internal] load metadata for docker.io/library/golang:1.24.1                                                                                                                          1.0s
 => [auth] library/golang:pull token for registry-1.docker.io                                                                                                                             0.0s
 => [internal] load .dockerignore                                                                                                                                                         0.0s
 => => transferring context: 44B                                                                                                                                                          0.0s
 => CACHED [build 1/5] FROM docker.io/library/golang:1.24.1@sha256:52ff1b35ff8de185bf9fd26c70077190cd0bed1e9f16a2d498ce907e5c421268                                                       0.0s
 => CACHED [stage-1 1/3] FROM gcr.io/distroless/static-debian12:latest@sha256:3d0f463de06b7ddff27684ec3bfd0b54a425149d0f8685308b1fdf297b0265e9                                            0.0s
 => [internal] load build context                                                                                                                                                         0.1s
 => => transferring context: 12.48MB                                                                                                                                                      0.1s
 => [build 2/5] RUN echo MYPATH:/home/das/Downloads/go_nix_simple COMMIT:a952e71 DATE:2025-04-16-03:21 VERSION:1.0.0     BUILDPLATFORM:${BUILDPLATFORM} TARGETPLATFORM:linux/amd64        0.1s
 => [build 3/5] WORKDIR /go/src                                                                                                                                                           0.0s
 => [build 4/5] COPY . .                                                                                                                                                                  0.1s
 => [build 5/5] RUN GOPROXY=http://127.0.0.1:8888     CGO_ENABLED=0 go build     -o /go/bin/go_nix_simple     ./cmd/go_nix_simple/go_nix_simple.go                                        7.7s
 => [stage-1 2/3] COPY --from=build --chmod=544 /go/bin/go_nix_simple /                                                                                                                   0.0s
 => [stage-1 3/3] COPY --from=build --chmod=444 /go/src/VERSION /                                                                                                                         0.0s
 => exporting to image                                                                                                                                                                    0.1s
 => => exporting layers                                                                                                                                                                   0.1s
 => => writing image sha256:15d4902b5c84d3771320e0e2c80605fae10e5e1ce1de2692932d47ac8ed60e3a                                                                                              0.0s
 => => naming to docker.io/randomizedcoder/go-nix-simple-distroless:1.0.0                                                                                                                 0.0s
 => => naming to docker.io/randomizedcoder/go-nix-simple-distroless:latest                                                                                                                0.0s
[] Finished builddocker_go-nix-simple-distroless. Duration: 9319 ms.
[] Starting nix_build_docker_gomod2nix...
warning: Git tree '/home/das/Downloads/go_nix_simple' is dirty
warning: input 'gomod2nix' has an override for a non-existent input 'utils'
[] Finished nix_build_docker_gomod2nix. Duration: 23296 ms.
[] Starting nix_build_docker_gomod2nix_load...
ee3c3c94f535: Loading layer [==================================================>]  8.274MB/8.274MB
f91061502278: Loading layer [==================================================>]  9.155MB/9.155MB
0c3944774c1e: Loading layer [==================================================>]  10.24kB/10.24kB
67ffbf7a29b2: Loading layer [==================================================>]  10.24kB/10.24kB
The image randomizedcoder/go-nix-simple-gomod2nix:latest already exists, renaming the old one with ID sha256:10b4ba765f411bf99ea8e66f7d3ab564b07866cf15ffc27e1243863975cbbeb0 to empty string
Loaded image: randomizedcoder/go-nix-simple-gomod2nix:latest
[] Finished nix_build_docker_gomod2nix_load. Duration: 536 ms.
docker image ls randomizedcoder/go-nix-simple;
REPOSITORY                      TAG       IMAGE ID       CREATED        SIZE
randomizedcoder/go-nix-simple   latest    8092239a5218   55 years ago   12.8MB
docker image ls randomizedcoder/go-nix-simple-distroless;
REPOSITORY                                 TAG       IMAGE ID       CREATED          SIZE
randomizedcoder/go-nix-simple-distroless   1.0.0     15d4902b5c84   24 seconds ago   14.3MB
randomizedcoder/go-nix-simple-distroless   latest    15d4902b5c84   24 seconds ago   14.3MB
docker image ls randomizedcoder/go-nix-simple-gomod2nix;
REPOSITORY                                TAG       IMAGE ID       CREATED        SIZE
randomizedcoder/go-nix-simple-gomod2nix   latest    a368a8ac838e   55 years ago   54.6MB
```

### make when cached
```
[das@t:~/Downloads/go_nix_simple]$ make
[] Starting nix_build_docker...
warning: Git tree '/home/das/Downloads/go_nix_simple' is dirty
warning: input 'gomod2nix' has an override for a non-existent input 'utils'
[] Finished nix_build_docker. Duration: 3548 ms.
[] Starting nix_build_docker_load...
Loaded image: randomizedcoder/go-nix-simple:latest
[] Finished nix_build_docker_load. Duration: 124 ms.
[] Starting builddocker_go-nix-simple-distroless...
================================
Make builddocker_go_nix_simple randomizedcoder/go-nix-simple-distroless:1.0.0
[+] Building 1.4s (14/14) FINISHED                                                                                                                                              docker:default
 => [internal] load build definition from Containerfile                                                                                                                                   0.0s
 => => transferring dockerfile: 1.61kB                                                                                                                                                    0.0s
 => [internal] load metadata for docker.io/library/golang:1.24.1                                                                                                                          0.6s
 => [internal] load metadata for gcr.io/distroless/static-debian12:latest                                                                                                                 0.4s
 => [internal] load .dockerignore                                                                                                                                                         0.0s
 => => transferring context: 44B                                                                                                                                                          0.0s
 => [stage-1 1/3] FROM gcr.io/distroless/static-debian12:latest@sha256:3d0f463de06b7ddff27684ec3bfd0b54a425149d0f8685308b1fdf297b0265e9                                                   0.0s
 => CACHED [build 1/5] FROM docker.io/library/golang:1.24.1@sha256:52ff1b35ff8de185bf9fd26c70077190cd0bed1e9f16a2d498ce907e5c421268                                                       0.0s
 => [internal] load build context                                                                                                                                                         0.0s
 => => transferring context: 1.44kB                                                                                                                                                       0.0s
 => [build 2/5] RUN echo MYPATH:/home/das/Downloads/go_nix_simple COMMIT:a952e71 DATE:2025-04-16-03:34 VERSION:1.0.0     BUILDPLATFORM:${BUILDPLATFORM} TARGETPLATFORM:linux/amd64        0.1s
 => [build 3/5] WORKDIR /go/src                                                                                                                                                           0.0s
 => [build 4/5] COPY . .                                                                                                                                                                  0.1s
 => [build 5/5] RUN --mount=type=cache,target=/go/pkg/mod     --mount=type=cache,target=/root/.cache/go-build     CGO_ENABLED=0 go build     -o /go/bin/go_nix_simple     ./cmd/go_nix_s  0.5s
 => CACHED [stage-1 2/3] COPY --from=build --chmod=544 /go/bin/go_nix_simple /                                                                                                            0.0s
 => CACHED [stage-1 3/3] COPY --from=build --chmod=444 /go/src/VERSION /                                                                                                                  0.0s
 => exporting to image                                                                                                                                                                    0.0s
 => => exporting layers                                                                                                                                                                   0.0s
 => => writing image sha256:15d4902b5c84d3771320e0e2c80605fae10e5e1ce1de2692932d47ac8ed60e3a                                                                                              0.0s
 => => naming to docker.io/randomizedcoder/go-nix-simple-distroless:1.0.0                                                                                                                 0.0s
 => => naming to docker.io/randomizedcoder/go-nix-simple-distroless:latest                                                                                                                0.0s
[] Finished builddocker_go-nix-simple-distroless. Duration: 1524 ms.
[] Starting builddocker_go-nix-simple-distroless-athens...
================================
Make builddocker_go_nix_simple randomizedcoder/go-nix-simple-distroless-athens:1.0.0
[+] Building 8.0s (14/14) FINISHED                                                                                                                                              docker:default
 => [internal] load build definition from Containerfile_athens                                                                                                                            0.0s
 => => transferring dockerfile: 1.61kB                                                                                                                                                    0.0s
 => [internal] load metadata for gcr.io/distroless/static-debian12:latest                                                                                                                 0.3s
 => [internal] load metadata for docker.io/library/golang:1.24.1                                                                                                                          0.2s
 => [internal] load .dockerignore                                                                                                                                                         0.0s
 => => transferring context: 44B                                                                                                                                                          0.0s
 => [build 1/5] FROM docker.io/library/golang:1.24.1@sha256:52ff1b35ff8de185bf9fd26c70077190cd0bed1e9f16a2d498ce907e5c421268                                                              0.0s
 => [stage-1 1/3] FROM gcr.io/distroless/static-debian12:latest@sha256:3d0f463de06b7ddff27684ec3bfd0b54a425149d0f8685308b1fdf297b0265e9                                                   0.0s
 => [internal] load build context                                                                                                                                                         0.0s
 => => transferring context: 1.44kB                                                                                                                                                       0.0s
 => CACHED [build 2/5] RUN echo MYPATH:/home/das/Downloads/go_nix_simple COMMIT:a952e71 DATE:2025-04-16-03:34 VERSION:1.0.0     BUILDPLATFORM:${BUILDPLATFORM} TARGETPLATFORM:linux/amd6  0.0s
 => CACHED [build 3/5] WORKDIR /go/src                                                                                                                                                    0.0s
 => CACHED [build 4/5] COPY . .                                                                                                                                                           0.0s
 => [build 5/5] RUN GOPROXY=http://localhost:8888     CGO_ENABLED=0 go build     -o /go/bin/go_nix_simple     ./cmd/go_nix_simple/go_nix_simple.go                                        7.6s
 => CACHED [stage-1 2/3] COPY --from=build --chmod=544 /go/bin/go_nix_simple /                                                                                                            0.0s
 => CACHED [stage-1 3/3] COPY --from=build --chmod=444 /go/src/VERSION /                                                                                                                  0.0s
 => exporting to image                                                                                                                                                                    0.0s
 => => exporting layers                                                                                                                                                                   0.0s
 => => writing image sha256:15d4902b5c84d3771320e0e2c80605fae10e5e1ce1de2692932d47ac8ed60e3a                                                                                              0.0s
 => => naming to docker.io/randomizedcoder/go-nix-simple-distroless-athens:1.0.0                                                                                                          0.0s
 => => naming to docker.io/randomizedcoder/go-nix-simple-distroless-athens:latest                                                                                                         0.0s
[] Finished builddocker_go-nix-simple-distroless-athens. Duration: 8107 ms.
[] Starting nix_build_docker_gomod2nix...
warning: Git tree '/home/das/Downloads/go_nix_simple' is dirty
warning: input 'gomod2nix' has an override for a non-existent input 'utils'
[] Finished nix_build_docker_gomod2nix. Duration: 3541 ms.
[] Starting nix_build_docker_gomod2nix_load...
Loaded image: randomizedcoder/go-nix-simple-gomod2nix:latest
[] Finished nix_build_docker_gomod2nix_load. Duration: 410 ms.
docker image ls randomizedcoder/go-nix-simple;
REPOSITORY                      TAG       IMAGE ID       CREATED        SIZE
randomizedcoder/go-nix-simple   latest    376a016de402   55 years ago   12.8MB
docker image ls randomizedcoder/go-nix-simple-distroless;
REPOSITORY                                 TAG       IMAGE ID       CREATED          SIZE
randomizedcoder/go-nix-simple-distroless   1.0.0     15d4902b5c84   11 minutes ago   14.3MB
randomizedcoder/go-nix-simple-distroless   latest    15d4902b5c84   11 minutes ago   14.3MB
docker image ls randomizedcoder/go-nix-simple-distroless-athens;
REPOSITORY                                        TAG       IMAGE ID       CREATED          SIZE
randomizedcoder/go-nix-simple-distroless-athens   1.0.0     15d4902b5c84   11 minutes ago   14.3MB
randomizedcoder/go-nix-simple-distroless-athens   latest    15d4902b5c84   11 minutes ago   14.3MB
docker image ls randomizedcoder/go-nix-simple-gomod2nix;
REPOSITORY                                TAG       IMAGE ID       CREATED        SIZE
randomizedcoder/go-nix-simple-gomod2nix   latest    865816858e7c   55 years ago   54.6MB
```

### make again and again

Nix _does_ cache, but this is for all the code

```
[das@t:~/Downloads/go_nix_simple]$ make nix_build_go-nix-simple
[] Starting nix_build_go-nix-simple...
warning: Git tree '/home/das/Downloads/go_nix_simple' is dirty
[] Finished nix_build_go-nix-simple. Duration: 16395 ms.           <----- SLOW

[das@t:~/Downloads/go_nix_simple]$ make nix_build_go-nix-simple
[] Starting nix_build_go-nix-simple...
warning: Git tree '/home/das/Downloads/go_nix_simple' is dirty
[] Finished nix_build_go-nix-simple. Duration: 907 ms.             <--- FAST

[das@t:~/Downloads/go_nix_simple]$ make nix_build_go-nix-simple
[] Starting nix_build_go-nix-simple...
warning: Git tree '/home/das/Downloads/go_nix_simple' is dirty
[] Finished nix_build_go-nix-simple. Duration: 899 ms.             <--- FAST

[das@t:~/Downloads/go_nix_simple]$ make nix_build_go-nix-simple
[] Starting nix_build_go-nix-simple...
warning: Git tree '/home/das/Downloads/go_nix_simple' is dirty
[] Finished nix_build_go-nix-simple. Duration: 889 ms.             <--- FAST

[das@t:~/Downloads/go_nix_simple]$ make nix_build_go-nix-simple
[] Starting nix_build_go-nix-simple...
warning: Git tree '/home/das/Downloads/go_nix_simple' is dirty
[] Finished nix_build_go-nix-simple. Duration: 888 ms.             <--- FAST
```

### Changing the go code

In thoery, buildGoApplication/gomod2nix should be faster than buildGoModule if we make a small change to the go code.

To test this, I just changed the sleep time, and rebuilt.  The results is that gomod2nix is actually still slower.  ? :(

Maybe this isn't a great example, becasue it doesn't have many dependacies, and I'm not building multiple go projects
through the same nix cache?

```
[das@t:~/Downloads/go_nix_simple]$ make
[] Starting nix_build_docker...
warning: Git tree '/home/das/Downloads/go_nix_simple' is dirty
warning: input 'gomod2nix' has an override for a non-existent input 'utils'
[] Finished nix_build_docker. Duration: 20674 ms.
[] Starting nix_build_docker_load...
7e146824c6d6: Loading layer [==================================================>]  8.274MB/8.274MB
0c3944774c1e: Loading layer [==================================================>]  10.24kB/10.24kB
a51ff0f06837: Loading layer [==================================================>]  10.24kB/10.24kB
The image randomizedcoder/go-nix-simple:latest already exists, renaming the old one with ID sha256:376a016de4025c767e8e60ccc8bf768e82f9e39910b42807b2574e1ef66a120d to empty string
Loaded image: randomizedcoder/go-nix-simple:latest
[] Finished nix_build_docker_load. Duration: 200 ms.
[] Starting builddocker_go-nix-simple-distroless...
================================
Make builddocker_go_nix_simple randomizedcoder/go-nix-simple-distroless:1.0.0
[+] Building 2.2s (15/15) FINISHED                                                                                                                                              docker:default
 => [internal] load build definition from Containerfile                                                                                                                                   0.0s
 => => transferring dockerfile: 1.61kB                                                                                                                                                    0.0s
 => [internal] load metadata for docker.io/library/golang:1.24.1                                                                                                                          1.1s
 => [internal] load metadata for gcr.io/distroless/static-debian12:latest                                                                                                                 0.5s
 => [auth] library/golang:pull token for registry-1.docker.io                                                                                                                             0.0s
 => [internal] load .dockerignore                                                                                                                                                         0.0s
 => => transferring context: 44B                                                                                                                                                          0.0s
 => [internal] load build context                                                                                                                                                         0.0s
 => => transferring context: 30.49kB                                                                                                                                                      0.0s
 => CACHED [build 1/5] FROM docker.io/library/golang:1.24.1@sha256:52ff1b35ff8de185bf9fd26c70077190cd0bed1e9f16a2d498ce907e5c421268                                                       0.0s
 => CACHED [stage-1 1/3] FROM gcr.io/distroless/static-debian12:latest@sha256:3d0f463de06b7ddff27684ec3bfd0b54a425149d0f8685308b1fdf297b0265e9                                            0.0s
 => [build 2/5] RUN echo MYPATH:/home/das/Downloads/go_nix_simple COMMIT:a952e71 DATE:2025-04-16-03:46 VERSION:1.0.0     BUILDPLATFORM:${BUILDPLATFORM} TARGETPLATFORM:linux/amd64        0.1s
 => [build 3/5] WORKDIR /go/src                                                                                                                                                           0.0s
 => [build 4/5] COPY . .                                                                                                                                                                  0.1s
 => [build 5/5] RUN --mount=type=cache,target=/go/pkg/mod     --mount=type=cache,target=/root/.cache/go-build     CGO_ENABLED=0 go build     -o /go/bin/go_nix_simple     ./cmd/go_nix_s  0.6s
 => [stage-1 2/3] COPY --from=build --chmod=544 /go/bin/go_nix_simple /                                                                                                                   0.0s
 => [stage-1 3/3] COPY --from=build --chmod=444 /go/src/VERSION /                                                                                                                         0.0s
 => exporting to image                                                                                                                                                                    0.1s
 => => exporting layers                                                                                                                                                                   0.1s
 => => writing image sha256:b3d4f69b30fa926ed75487550aa0c611c79cf88898cc73a5b718122843a252c4                                                                                              0.0s
 => => naming to docker.io/randomizedcoder/go-nix-simple-distroless:1.0.0                                                                                                                 0.0s
 => => naming to docker.io/randomizedcoder/go-nix-simple-distroless:latest                                                                                                                0.0s
[] Finished builddocker_go-nix-simple-distroless. Duration: 2321 ms.
[] Starting builddocker_go-nix-simple-distroless-athens...
================================
Make builddocker_go_nix_simple randomizedcoder/go-nix-simple-distroless-athens:1.0.0
[+] Building 8.1s (14/14) FINISHED                                                                                                                                              docker:default
 => [internal] load build definition from Containerfile_athens                                                                                                                            0.0s
 => => transferring dockerfile: 1.61kB                                                                                                                                                    0.0s
 => [internal] load metadata for docker.io/library/golang:1.24.1                                                                                                                          0.2s
 => [internal] load metadata for gcr.io/distroless/static-debian12:latest                                                                                                                 0.3s
 => [internal] load .dockerignore                                                                                                                                                         0.0s
 => => transferring context: 44B                                                                                                                                                          0.0s
 => [build 1/5] FROM docker.io/library/golang:1.24.1@sha256:52ff1b35ff8de185bf9fd26c70077190cd0bed1e9f16a2d498ce907e5c421268                                                              0.0s
 => [internal] load build context                                                                                                                                                         0.0s
 => => transferring context: 1.44kB                                                                                                                                                       0.0s
 => [stage-1 1/3] FROM gcr.io/distroless/static-debian12:latest@sha256:3d0f463de06b7ddff27684ec3bfd0b54a425149d0f8685308b1fdf297b0265e9                                                   0.0s
 => CACHED [build 2/5] RUN echo MYPATH:/home/das/Downloads/go_nix_simple COMMIT:a952e71 DATE:2025-04-16-03:46 VERSION:1.0.0     BUILDPLATFORM:${BUILDPLATFORM} TARGETPLATFORM:linux/amd6  0.0s
 => CACHED [build 3/5] WORKDIR /go/src                                                                                                                                                    0.0s
 => CACHED [build 4/5] COPY . .                                                                                                                                                           0.0s
 => [build 5/5] RUN GOPROXY=http://localhost:8888     CGO_ENABLED=0 go build     -o /go/bin/go_nix_simple     ./cmd/go_nix_simple/go_nix_simple.go                                        7.6s
 => CACHED [stage-1 2/3] COPY --from=build --chmod=544 /go/bin/go_nix_simple /                                                                                                            0.0s
 => CACHED [stage-1 3/3] COPY --from=build --chmod=444 /go/src/VERSION /                                                                                                                  0.0s
 => exporting to image                                                                                                                                                                    0.0s
 => => exporting layers                                                                                                                                                                   0.0s
 => => writing image sha256:b3d4f69b30fa926ed75487550aa0c611c79cf88898cc73a5b718122843a252c4                                                                                              0.0s
 => => naming to docker.io/randomizedcoder/go-nix-simple-distroless-athens:1.0.0                                                                                                          0.0s
 => => naming to docker.io/randomizedcoder/go-nix-simple-distroless-athens:latest                                                                                                         0.0s
[] Finished builddocker_go-nix-simple-distroless-athens. Duration: 8147 ms.
[] Starting nix_build_docker_gomod2nix...
warning: Git tree '/home/das/Downloads/go_nix_simple' is dirty
warning: input 'gomod2nix' has an override for a non-existent input 'utils'
[] Finished nix_build_docker_gomod2nix. Duration: 23177 ms.
[] Starting nix_build_docker_gomod2nix_load...
7e146824c6d6: Loading layer [==================================================>]  8.274MB/8.274MB
18d2d6b59d63: Loading layer [==================================================>]  9.155MB/9.155MB
0c3944774c1e: Loading layer [==================================================>]  10.24kB/10.24kB
ae4b3b5c1741: Loading layer [==================================================>]  10.24kB/10.24kB
The image randomizedcoder/go-nix-simple-gomod2nix:latest already exists, renaming the old one with ID sha256:865816858e7c9042f2f0fe649b4363b23da457ecdb00a2998f1ed12da1c47608 to empty string
Loaded image: randomizedcoder/go-nix-simple-gomod2nix:latest
[] Finished nix_build_docker_gomod2nix_load. Duration: 545 ms.
docker image ls randomizedcoder/go-nix-simple;
REPOSITORY                      TAG       IMAGE ID       CREATED        SIZE
randomizedcoder/go-nix-simple   latest    443e2dcf980b   55 years ago   12.8MB
docker image ls randomizedcoder/go-nix-simple-distroless;
REPOSITORY                                 TAG       IMAGE ID       CREATED          SIZE
randomizedcoder/go-nix-simple-distroless   1.0.0     b3d4f69b30fa   32 seconds ago   14.3MB
randomizedcoder/go-nix-simple-distroless   latest    b3d4f69b30fa   32 seconds ago   14.3MB
docker image ls randomizedcoder/go-nix-simple-distroless-athens;
REPOSITORY                                        TAG       IMAGE ID       CREATED          SIZE
randomizedcoder/go-nix-simple-distroless-athens   1.0.0     b3d4f69b30fa   32 seconds ago   14.3MB
randomizedcoder/go-nix-simple-distroless-athens   latest    b3d4f69b30fa   32 seconds ago   14.3MB
docker image ls randomizedcoder/go-nix-simple-gomod2nix;
REPOSITORY                                TAG       IMAGE ID       CREATED        SIZE
randomizedcoder/go-nix-simple-gomod2nix   latest    fc35f6f19127   55 years ago   54.6MB
```


# ls -la

```
[das@t:~/Downloads/go_nix_simple]$ ls -la
total 136
drwxr-xr-x   6 das users  4096 Apr 15 10:18 .
drwxr-xr-x 199 das users 61440 Apr 14 14:56 ..
drwxr-xr-x   3 das users  4096 Apr 15 09:48 build
drwxr-xr-x   3 das users  4096 Apr 14 14:57 cmd
-rw-r--r--   1 das users     4 Apr 15 08:57 .dockerignore
drwxr-xr-x   3 das users  4096 Apr 14 15:34 docs
-rw-r--r--   1 das users  1497 Apr 14 15:05 flake.lock
-rw-r--r--   1 das users  3076 Apr 15 10:03 flake.nix
drwxr-xr-x   8 das users  4096 Apr 15 09:11 .git
-rw-r--r--   1 das users     6 Apr 14 15:14 .gitignore
-rw-r--r--   1 das users   588 Apr 14 15:00 go.mod
-rw-r--r--   1 das users  3021 Apr 14 15:00 go.sum
-rw-r--r--   1 das users  1072 Apr 14 14:56 LICENSE
-rw-r--r--   1 das users  3458 Apr 15 10:17 Makefile
-rw-r--r--   1 das users  9711 Apr 15 10:18 README.md
lrwxrwxrwx   1 das users    64 Apr 15 10:18 result -> /nix/store/688h33ik6x96xq384jr2g7mxn757dsmr-go-nix-simple.tar.gz
-rw-r--r--   1 das users     5 Apr 14 14:58 VERSION

[das@t:~/Downloads/go_nix_simple]$ ls -lahL result
-r--r--r-- 2 root root 4.5M Dec 31  1969 result
```

# tar -tzvf result

This shows the layers build by nix

```
[das@t:~/Downloads/go_nix_simple]$ tar -tzvf result
-r--r--r-- 0/0          327680 1969-12-31 16:00 b7f712dabf336ac1018bcd8173a3fffbe1e7529ae81dd6bee803e32fed0a50b6.tar
-r--r--r-- 0/0           40960 1969-12-31 16:00 8fa10c0194df9b7c054c90dbe482585f768a54428fc90a5b78a0066a123b1bba.tar
-r--r--r-- 0/0         2406400 1969-12-31 16:00 48c0fb67386ed713921fcc0468be23231d0872fa67ccc8ea3929df4656b6ddfc.tar
-r--r--r-- 0/0            1536 1969-12-31 16:00 4d049f83d9cf21d1f5cc0e11deaf36df02790d0e60c1a3829538fb4b61685368.tar
-r--r--r-- 0/0            2560 1969-12-31 16:00 af5aa97ebe6ce1604747ec1e21af7136ded391bcabe4acef882e718a87c86bcc.tar
-r--r--r-- 0/0            2560 1969-12-31 16:00 6f1cdceb6a3146f0ccb986521156bef8a422cdbb0863396f7f751f575ba308f4.tar
-r--r--r-- 0/0            2560 1969-12-31 16:00 bbb6cacb8c82e4da4e8143e03351e939eab5e21ce0ef333c42e637af86c5217b.tar
-r--r--r-- 0/0            1536 1969-12-31 16:00 2a92d6ac9e4fcc274d5168b217ca4458a9fec6f094ead68d99c77073f08caac1.tar
-r--r--r-- 0/0           10240 1969-12-31 16:00 1a73b54f556b477f0a8b939d13c504a3b4f4db71f7a09c63afbc10acb3de5849.tar
-r--r--r-- 0/0            3072 1969-12-31 16:00 f4aee9e53c42a22ed82451218c3ea03d1eea8d6ca8fbe8eb4e950304ba8a8bb3.tar
-r--r--r-- 0/0          238592 1969-12-31 16:00 b336e209998fa5cf0eec3dabf93a21194198a35f4f75612d8da03693f8c30217.tar
-rw-r--r-- 0/0          583680 1969-12-31 16:00 38e0af94c91a262fbd1887cd2bd4cb1391326398f62493a36cb646b156d77b4d/layer.tar
-rw-r--r-- 0/0          133120 1969-12-31 16:00 3b0071b79b5f08b1151a49a826bd989a18951689b23e9ddc5f0d50e25c161e57/layer.tar
-rw-r--r-- 0/0         2928640 1969-12-31 16:00 67fe4cdb969cc13f67728b848d6ef725a707781961ff7b1d65b0d15d81fecff3/layer.tar
-rw-r--r-- 0/0         8273920 1969-12-31 16:00 0f9c4334b1a6038ab1734e7570b27b88a04acf29071b1a071b384f297049ea76/layer.tar
-r--r--r-- nobody/nogroup 10240 1969-12-31 16:00 456e1fd34b9dcbceb2b6b3709b5177cc8102c1dd0cfc105052f7977472f8011c/layer.tar
-rw-r--r-- 0/0             4943 1969-12-31 16:00 5e59c68ce19c78401b34c081369f46b206295959ea3967a76b6a0586755d8075.json
-rw-r--r-- 0/0             1593 1969-12-31 16:00 manifest.json
```

# Dive screenshots

Here are screenshots of the x2 different images.  We can see the

## Layer 1 nix built
<img src="docs/images/Screenshot From 2025-04-15 10-23-13.png" alt="Layer 1/9 libunistring" width="90%" height="90%">

## Layer 15 nix built go_nix_simple
<img src="docs/images/Screenshot From 2025-04-15 10-27-00.png" alt="Layer 4/9 libgcc" width="90%" height="90%">

## Layer 1 docker built
<img src="docs/images/Screenshot From 2025-04-15 10-27-44.png" alt="Layer 9/9 go_nix_simple" width="90%" height="90%">

## Layer 12 docker built go_nix_simple
<img src="docs/images/Screenshot From 2025-04-15 10-27-36.png" alt="Layer 9/9 go_nix_simple" width="90%" height="90%">


# Athens

Deploy athens caching proxy for golang
```
make deploy_athens
```
This allows the Docker build to leverage the cache.

[https://github.com/gomods/athens](https://github.com/gomods/athens)

[https://docs.gomods.io/walkthrough/#with-docker](https://docs.gomods.io/walkthrough/#with-docker)


I also tried to nix build athens into a container, but it doesn't run.
```
[das@t:~/Downloads/go_nix_simple]$ make nix_build_athens
nix build .#athens-nix-image
warning: Git tree '/home/das/Downloads/go_nix_simple' is dirty
docker load < result
dffb2d8b972b: Loading layer [==================================================>]  46.14MB/46.14MB
250fef83d04b: Loading layer [==================================================>]  10.24kB/10.24kB
Loaded image: randomizedcoder/athens-nix:latest

[das@t:~/Downloads/go_nix_simple]$ docker image ls | grep athens
gomods/athens                                                                              latest                             1f858fb0105c   5 months ago    176MB
randomizedcoder/athens-nix                                                                 latest                             52cf8644c591   55 years ago    50.7MB

[das@t:~/Downloads/go_nix_simple]$ docker run -p 8888:8888 randomizedcoder/athens-nix:latest
2025/04/15 22:46:39 Running dev mode with default settings, consult config when you're ready to run in production
INFO[10:46PM]: Exporter not specified. Traces won't be exported
FATAL[10:46PM]: Could not create App    error=adding proxy routes: exec: "go": executable file not found in $PATH
```

I don't think you can use GOPROXY with buildGoModule:
https://github.com/NixOS/nixpkgs/blob/589c31662739027f6b802f138fd12f4493ad68de/pkgs/build-support/go/module.nix#L89

Actually, it's because it's disabled here:

```
    configurePhase = args.configurePhase or (''
      runHook preConfigure

      export GOCACHE=$TMPDIR/go-cache
      export GOPATH="$TMPDIR/go"
      export GOPROXY=off                        <---- DISABLED
      export GOSUMDB=off                              <---- Not sure why they do this.  Scary!
```
https://github.com/NixOS/nixpkgs/blob/589c31662739027f6b802f138fd12f4493ad68de/pkgs/build-support/go/module.nix#L180



https://github.com/NixOS/nixpkgs/blob/master/pkgs/build-support/go/module.nix#L105



## Nix Go links
https://nixos.wiki/wiki/Go
https://nixos.org/manual/nixpkgs/stable/#sec-language-go


## Gomod2nix links
https://www.tweag.io/blog/2021-03-04-gomod2nix/

https://jameswillia.ms/posts/go-nix-containers.html

https://xeiaso.net/blog/nix-flakes-go-programs/


## Misc links

https://tmp.bearblog.dev/minimal-containers-using-nix/

https://jamey.thesharps.us/2021/02/02/docker-containers-nix/

https://spacekookie.de/blog/ocitools-in-nixos/

https://www.gopaddy.ch/en/posts/b14028e/

https://grahamc.com/blog/nix-and-layered-docker-images/
