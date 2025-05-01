# go_nix_simple

This is an example repo with a relatively simple [go program](./cmd/go_nix_simple/go_nix_simple.go).

The intention of the repo is to test/demontrate different methods for builing containers and to measure the performance.

In particular, I was interested to explore if Nix could help speedup builds.  Spoilier alert: Nix may be repeatable, but it is not fast.



The example program is essentially a [loop](./cmd/go_nix_simple/go_nix_simple.go) printing out a counter and has prometheus counters.

I ended up adding in a bunch of other libraries (database/sql, clickhouse-go, pyroscope-go, go-redis/v9), to try to see if the nix gomod2nix improves performance.  Spoilier alert: Doesn't seem to.


The other thing this repo does is demonstrate how small the container can be.  Scratch clearly wins here, and I wonder why distroless is often recommended.


Friends on the Gopher slack suggested the upx might break the build, but I don't see evidence of this on my amd64 machine.  Maybe it breaks on Apple? Easy fix is to not use Apples.



## Summary

```
=============================================================================================
Build Summary - From Directory: ./output/20250428_112359
=============================================================================================
Target                                                      | Time (ms) | Size (MB) | Layers
------------------------------------------------------------|-----------|-----------|--------
build-image-docker-distroless-athens-noupx                  |     35101 |     15.22 |     12
build-image-docker-distroless-athens-upx                    |     38841 |      5.87 |     12
build-image-docker-distroless-docker-noupx                  |      2213 |     15.22 |     12
build-image-docker-distroless-docker-upx                    |      2075 |      5.87 |     12
build-image-docker-distroless-http-noupx                    |     32713 |     15.22 |     12
build-image-docker-distroless-http-upx                      |     36895 |      5.87 |     12
build-image-docker-distroless-none-noupx                    |     27626 |     15.22 |     12
build-image-docker-distroless-none-upx                      |     35659 |      5.87 |     12
build-image-docker-scratch-athens-noupx                     |     29616 |     13.52 |      1
build-image-docker-scratch-athens-upx                       |     29459 |      4.18 |      1
build-image-docker-scratch-docker-noupx                     |      2452 |     13.52 |      1
build-image-docker-scratch-docker-upx                       |      2378 |      4.18 |      1  <--- Docker caching is awesome!
build-image-docker-scratch-http-noupx                       |     37161 |     13.52 |      1
build-image-docker-scratch-http-upx                         |     31447 |      4.18 |      1
build-image-docker-scratch-none-noupx                       |     31228 |     13.52 |      1
build-image-docker-scratch-none-upx                         |     32083 |      4.18 |      1
build-image-nix-distroless-buildgomodule-noupx              |     55890 |     17.68 |     18
build-image-nix-distroless-buildgomodule-upx                |     15613 |      5.87 |     15
build-image-nix-distroless-gomod2nix-noupx                  |     63098 |     29.08 |     18
build-image-nix-distroless-gomod2nix-upx                    |     18871 |      5.69 |     15
build-image-nix-scratch-buildgomodule-noupx                 |      8725 |     15.78 |      7
build-image-nix-scratch-buildgomodule-upx                   |      8213 |      3.97 |      4
build-image-nix-scratch-gomod2nix-noupx                     |      9110 |     27.18 |      7
build-image-nix-scratch-gomod2nix-upx                       |      8229 |      3.79 |      4  <--- Yay for Nix caching
=============================================================================================
```

- distroless = [gcr.io/distroless/static-debian12](https://github.com/GoogleContainerTools/distroless?tab=readme-ov-file#what-images-are-available)
- scratch = [https://hub.docker.com/_/scratch](https://hub.docker.com/_/scratch)
- buildGoApplication ( [gomod2nix](https://github.com/nix-community/gomod2nix) )
- [buildGoModule](https://nixos.org/manual/nixpkgs/stable/#sec-language-go)

Please see the [Makefile](./Makefile) for how to run this

## Quick Start

```
git clone https://github.com/randomizedcoder/go_nix_simple/
cd go_nix_simple
make deploy_athens           <--- optional
make squid                   <--- optional
make generate-containerfiles
make build-validator
make
make run-valdiator
```

# Combinations and Permutations

- Builder: Nix-buildGoModule, Nix-buildGoApplication, Docker-build, Bazel-build, Bazel-build-nix
- Final base container: Distroless, Scratch
- Caching: Docker, Athens, Nix, HTTP-cache, No-cache, Bazel
- Executable packer: UPX, none

## Performance tips

Even if you aren't interested in Nix, some top tips for improving container build times for golang:

### .dockerignore

- You probably have `COPY . .` in your Containerfile, so this copies the .git folder, which has
  many files and you probably don't need when building your continaer
- Tell your docker build not to copy this, and it will be faster
```
echo ".git" > .dockerignore                     <--- Win!
```

### Docker build cache

- Use the [docker build cache](https://github.com/randomizedcoder/go_nix_simple/blob/main/build/containers/go_nix_simple/Containerfile#L35).  This works great for local builds on your machine.
```
RUN --mount=type=cache,target=/go/pkg/mod \                 <--- Win!
    --mount=type=cache,target=/root/.cache/go-build \       <--- Win!   <---- This is the main win!
    CGO_ENABLED=0 go build \
    -o /go/bin/go_nix_simple \
    ./cmd/go_nix_simple/go_nix_simple.go
```
### Athens goproxy cache

- For you ci/cd build farm, assuming you can't use the docker cache, you can use [Athens to proxy/cache modules](https://github.com/randomizedcoder/go_nix_simple/blob/main/build/containers/go_nix_simple/Containerfile_athens#L44).

```
# https://go.dev/ref/mod#private-module-proxy-private
RUN GOPROXY=http://localhost:8888,https://proxy.golang.org,direct \    <--- Win!
    CGO_ENABLED=0 go build \
    -o /go/bin/go_nix_simple \
    ./cmd/go_nix_simple/go_nix_simple.go
```

To [deploy Athens locally on your machine](https://github.com/randomizedcoder/go_nix_simple/blob/main/Makefile#L122) for testing do:
```
git clone https://github.com/randomizedcoder/go_nix_simple/
cd go_nix_simple
make deploy_athens
```
This will deploy a local Athens proxy with disk cache.  ( Please note I'm using the non-standard port, cos I alreayd have Grafana running.)

```
[das@t:~/Downloads/go_nix_simple]$ make deploy_athens
================================
Make deploy_athens
docker compose \
        --file build/containers/athens/docker-compose-athens.yml \
        up -d --remove-orphans
[+] Running 1/1
 ✔ Container athens  Started                                                                                                                                                                                                                                                 0.1s

[das@t:~/Downloads/go_nix_simple]$ docker ps | grep athens
30992d98c8a0   gomods/athens:latest   "/sbin/tini -- athen…"   12 days ago   Up 6 seconds             athens
```

### Squid proxy cache

To allow testing of the builds via HTTP proxy cache, you can run up squid.  Squid doesn't really do much here, because all the downloads are HTTPS, so this is really just a HTTP CONNECT proxy.

Quick start: Deploy squid with "make squid"
```
[das@t:~/Downloads/go_nix_simple]$ make squid
docker build -t my-custom-squid:latest \
        -f ./build/containers/squid/Containerfile \
        ./build/containers/squid/
[+] Building 0.1s (7/7) FINISHED                                                                                                                                                                                                                                   docker:default
 => [internal] load build definition from Containerfile                                                                                                                                                                                                                      0.0s
 => => transferring dockerfile: 159B                                                                                                                                                                                                                                         0.0s
 => [internal] load metadata for docker.io/sameersbn/squid:latest                                                                                                                                                                                                            0.0s
 => [internal] load .dockerignore                                                                                                                                                                                                                                            0.0s
 => => transferring context: 2B                                                                                                                                                                                                                                              0.0s
 => [internal] load build context                                                                                                                                                                                                                                            0.0s
 => => transferring context: 33B                                                                                                                                                                                                                                             0.0s
 => [1/2] FROM docker.io/sameersbn/squid:latest                                                                                                                                                                                                                              0.0s
 => CACHED [2/2] COPY squid.conf /etc/squid/squid.conf                                                                                                                                                                                                                       0.0s
 => exporting to image                                                                                                                                                                                                                                                       0.0s
 => => exporting layers                                                                                                                                                                                                                                                      0.0s
 => => writing image sha256:601b90da83e8445705e3b03324551b9c42ab219a7ef8fe2ec4b402ef71cdc266                                                                                                                                                                                 0.0s
 => => naming to docker.io/library/my-custom-squid:latest                                                                                                                                                                                                                    0.0s
================================
Make deploy_squid
docker compose \
        --file build/containers/squid/docker-compose-squid.yml \
        up -d --remove-orphans
[+] Running 1/0
 ✔ Container squid  Running
```


The default squid config has a http deny, so to make a fully open squid, I just overwrite the /etc/squid/squid.conf.  DON'T USE THIS IN PRODUCTION or on the general internets!!
```
[das@t:~/Downloads/go_nix_simple]$ make create_squid
docker build -t my-custom-squid:latest \
        -f ./build/containers/squid/Containerfile \
        ./build/containers/squid/
[+] Building 0.3s (7/7) FINISHED                                                                                                                                                                                                                                   docker:default
 => [internal] load build definition from Containerfile                                                                                                                                                                                                                      0.0s
 => => transferring dockerfile: 159B                                                                                                                                                                                                                                         0.0s
 => [internal] load metadata for docker.io/sameersbn/squid:latest                                                                                                                                                                                                            0.0s
 => [internal] load .dockerignore                                                                                                                                                                                                                                            0.0s
 => => transferring context: 2B                                                                                                                                                                                                                                              0.0s
 => [internal] load build context                                                                                                                                                                                                                                            0.1s
 => => transferring context: 290.72kB                                                                                                                                                                                                                                        0.0s
 => [1/2] FROM docker.io/sameersbn/squid:latest                                                                                                                                                                                                                              0.1s
 => [2/2] COPY squid.conf /etc/squid/squid.conf                                                                                                                                                                                                                              0.0s
 => exporting to image                                                                                                                                                                                                                                                       0.0s
 => => exporting layers                                                                                                                                                                                                                                                      0.0s
 => => writing image sha256:601b90da83e8445705e3b03324551b9c42ab219a7ef8fe2ec4b402ef71cdc266                                                                                                                                                                                 0.0s
 => => naming to docker.io/library/my-custom-squid:latest                                                                                                                                                                                                                    0.0s
```


```
[das@t:~/Downloads/go_nix_simple]$ make deploy_squid
================================
Make deploy_squid
docker compose \
        --file build/containers/squid/docker-compose-squid.yml \
        up -d --remove-orphans
[+] Running 1/1
 ✔ Container squid  Started
```


## Containerfiles
For the docker builds, there is code that generates the container files, allowing different methods to be tested.

The [generate-containerfiles.go code](./cmd/generate-containerfiles/generate-containerfiles.go) is pretty simple and uses a [go template](./build/containers/go_nix_simple_refactor/Containerfile.tmpl).

```
[das@t:~/Downloads/go_nix_simple]$ make generate-containerfiles
[] Building Containerfile generator...
make[1]: Entering directory '/home/das/Downloads/go_nix_simple/cmd/generate-containerfiles'
go build -ldflags "-X main.commit=56bd2af -X main.date=2025-04-27-15:38 -X main.version=1.0.0" -o ./generate-containerfiles ./generate-containerfiles.go
make[1]: Leaving directory '/home/das/Downloads/go_nix_simple/cmd/generate-containerfiles'
[] Running Containerfile generator...
[] Starting  generate-containerfiles...
2025/04/27 08:38:17 Generator version: 1.0.0, commit: 56bd2af, built: 2025-04-27-15:38
2025/04/27 08:38:17 Generated 16 configuration combinations.
2025/04/27 08:38:17 Generated: build/containers/go_nix_simple_refactor/Containerfile.distroless.docker.noupx
2025/04/27 08:38:17 Generated: build/containers/go_nix_simple_refactor/Containerfile.distroless.docker.upx
2025/04/27 08:38:17 Generated: build/containers/go_nix_simple_refactor/Containerfile.distroless.athens.noupx
2025/04/27 08:38:17 Generated: build/containers/go_nix_simple_refactor/Containerfile.distroless.athens.upx
2025/04/27 08:38:17 Generated: build/containers/go_nix_simple_refactor/Containerfile.distroless.http.noupx
2025/04/27 08:38:17 Generated: build/containers/go_nix_simple_refactor/Containerfile.distroless.http.upx
2025/04/27 08:38:17 Generated: build/containers/go_nix_simple_refactor/Containerfile.distroless.none.noupx
2025/04/27 08:38:17 Generated: build/containers/go_nix_simple_refactor/Containerfile.distroless.none.upx
2025/04/27 08:38:17 Generated: build/containers/go_nix_simple_refactor/Containerfile.scratch.docker.noupx
2025/04/27 08:38:17 Generated: build/containers/go_nix_simple_refactor/Containerfile.scratch.docker.upx
2025/04/27 08:38:17 Generated: build/containers/go_nix_simple_refactor/Containerfile.scratch.athens.noupx
2025/04/27 08:38:17 Generated: build/containers/go_nix_simple_refactor/Containerfile.scratch.athens.upx
2025/04/27 08:38:17 Generated: build/containers/go_nix_simple_refactor/Containerfile.scratch.http.noupx
2025/04/27 08:38:17 Generated: build/containers/go_nix_simple_refactor/Containerfile.scratch.http.upx
2025/04/27 08:38:17 Generated: build/containers/go_nix_simple_refactor/Containerfile.scratch.none.noupx
2025/04/27 08:38:17 Generated: build/containers/go_nix_simple_refactor/Containerfile.scratch.none.upx
[] Finished  generate-containerfiles. Duration: 4 ms.
```

## Validation

To ensure the containers actually work, there is code that will instanciate each container and perform a basic check that the code works.

The code validates the print loop works, and the prometheus counters work.

The code can run in parrallel, so it's reasonably fast.

To build the validator do "make build-validator"
```
[das@t:~/Downloads/go_nix_simple]$ make build-validator
[] Building validator tool...
make[1]: Entering directory '/home/das/Downloads/go_nix_simple/cmd/validate-image'
go build -ldflags \
        "-X main.commit=56bd2af -X main.date=2025-04-28-17:43 -X main.version=1.0.0" \
        -o ./validate-image \
        ./validate-image.go
make[1]: Leaving directory '/home/das/Downloads/go_nix_simple/cmd/validate-image'
[] Finished building validator tool.

[das@t:~/Downloads/go_nix_simple]$
```

The validator has cli args.
```
[das@t:~/Downloads/go_nix_simple]$ ./cmd/validate-image/validate-image --help
Usage of ./cmd/validate-image/validate-image:
  -images string
        Comma-separated list of Docker image tags to validate (required)
  -log-target string
        Log line prefix to wait for (default "Hello 2 from")
  -metric-target string
        Prometheus metric name (with labels) to check (default "counters_main{function=\"loop\",type=\"count\",variable=\"tick\"}")
  -metric-threshold float
        Minimum value for the target metric (default 2)
  -parallel int
        Number of concurrent validation tests to run (default 1)
  -repo-prefix string
        Repository prefix (e.g., dockerhub username) for images (used with -images=all) (default "randomizedcoder")
  -timeout duration
        Timeout for each individual image validation (default 30s)
  -version string
        Version tag for images (used with -images=all) (default "1.0.0")
```

To run the validator do "make run-valdiator"

```
[das@t:~/Downloads/go_nix_simple]$ make run-valdiator
./cmd/validate-image/validate-image --parallel 8
2025/04/28 19:10:55.273589 Starting validation for 24 image(s) with parallelism 8 and timeout 30s
2025/04/28 19:10:55.273638 Worker 8 started
2025/04/28 19:10:55.273651 Worker 6 started
2025/04/28 19:10:55.273640 Worker 4 started
2025/04/28 19:10:55.273717 Worker 2 started
2025/04/28 19:10:55.273840 Worker 7 started
2025/04/28 19:10:55.273976 Worker 5 started
2025/04/28 19:10:55.273966 Worker 3 started
2025/04/28 19:10:55.273992 Worker 1 started
2025/04/28 19:11:13.260314 Worker 4: Finished validating randomizedcoder/nix-go-nix-simple-distroless-gomod2nix-noupx:1.0.0 (Overall Success: true, Duration: 17.986620965s)
2025/04/28 19:11:13.287024 Worker 7: Finished validating randomizedcoder/nix-go-nix-simple-scratch-buildgomodule-noupx:1.0.0 (Overall Success: true, Duration: 18.013146673s)
2025/04/28 19:11:13.671894 Worker 2: Finished validating randomizedcoder/nix-go-nix-simple-distroless-gomod2nix-upx:1.0.0 (Overall Success: true, Duration: 18.39813906s)
2025/04/28 19:11:13.714788 Worker 3: Finished validating randomizedcoder/nix-go-nix-simple-scratch-gomod2nix-noupx:1.0.0 (Overall Success: true, Duration: 18.440768358s)
2025/04/28 19:11:13.752754 Worker 5: Finished validating randomizedcoder/nix-go-nix-simple-scratch-buildgomodule-upx:1.0.0 (Overall Success: true, Duration: 18.478766987s)
2025/04/28 19:11:13.770745 Worker 1: Finished validating randomizedcoder/nix-go-nix-simple-scratch-gomod2nix-upx:1.0.0 (Overall Success: true, Duration: 18.49672876s)
2025/04/28 19:11:13.826077 Worker 6: Finished validating randomizedcoder/nix-go-nix-simple-distroless-buildgomodule-upx:1.0.0 (Overall Success: true, Duration: 18.55239331s)
2025/04/28 19:11:14.033032 Worker 8: Finished validating randomizedcoder/nix-go-nix-simple-distroless-buildgomodule-noupx:1.0.0 (Overall Success: true, Duration: 18.759387185s)
2025/04/28 19:11:31.595442 Worker 6: Finished validating randomizedcoder/docker-go-nix-simple-distroless-none-noupx:1.0.0 (Overall Success: true, Duration: 17.769349476s)
2025/04/28 19:11:31.650162 Worker 4: Finished validating randomizedcoder/docker-go-nix-simple-distroless-docker-noupx:1.0.0 (Overall Success: true, Duration: 18.38981985s)
2025/04/28 19:11:31.701032 Worker 7: Finished validating randomizedcoder/docker-go-nix-simple-distroless-docker-upx:1.0.0 (Overall Success: true, Duration: 18.413991268s)
2025/04/28 19:11:31.728167 Worker 2: Finished validating randomizedcoder/docker-go-nix-simple-distroless-athens-noupx:1.0.0 (Overall Success: true, Duration: 18.056259016s)
2025/04/28 19:11:31.933786 Worker 5: Finished validating randomizedcoder/docker-go-nix-simple-distroless-http-noupx:1.0.0 (Overall Success: true, Duration: 18.180995109s)
2025/04/28 19:11:31.977182 Worker 3: Finished validating randomizedcoder/docker-go-nix-simple-distroless-athens-upx:1.0.0 (Overall Success: true, Duration: 18.262380263s)
2025/04/28 19:11:32.324388 Worker 1: Finished validating randomizedcoder/docker-go-nix-simple-distroless-http-upx:1.0.0 (Overall Success: true, Duration: 18.553625353s)
2025/04/28 19:11:32.384047 Worker 8: Finished validating randomizedcoder/docker-go-nix-simple-distroless-none-upx:1.0.0 (Overall Success: true, Duration: 18.350999856s)
2025/04/28 19:11:49.699910 Worker 7: Finished validating randomizedcoder/docker-go-nix-simple-scratch-athens-noupx:1.0.0 (Overall Success: true, Duration: 17.998858123s)
2025/04/28 19:11:49.699922 Worker 7 finished
2025/04/28 19:11:49.750746 Worker 6: Finished validating randomizedcoder/docker-go-nix-simple-scratch-docker-noupx:1.0.0 (Overall Success: true, Duration: 18.155284158s)
2025/04/28 19:11:49.750764 Worker 6 finished
2025/04/28 19:11:49.770945 Worker 5: Finished validating randomizedcoder/docker-go-nix-simple-scratch-http-noupx:1.0.0 (Overall Success: true, Duration: 17.837142987s)
2025/04/28 19:11:49.770959 Worker 5 finished
2025/04/28 19:11:50.120154 Worker 4: Finished validating randomizedcoder/docker-go-nix-simple-scratch-docker-upx:1.0.0 (Overall Success: true, Duration: 18.469973967s)
2025/04/28 19:11:50.120167 Worker 4 finished
2025/04/28 19:11:50.149637 Worker 2: Finished validating randomizedcoder/docker-go-nix-simple-scratch-athens-upx:1.0.0 (Overall Success: true, Duration: 18.421451435s)
2025/04/28 19:11:50.149653 Worker 2 finished
2025/04/28 19:11:50.173197 Worker 1: Finished validating randomizedcoder/docker-go-nix-simple-scratch-none-noupx:1.0.0 (Overall Success: true, Duration: 17.848789409s)
2025/04/28 19:11:50.173210 Worker 1 finished
2025/04/28 19:11:50.425642 Worker 3: Finished validating randomizedcoder/docker-go-nix-simple-scratch-http-upx:1.0.0 (Overall Success: true, Duration: 18.448445227s)
2025/04/28 19:11:50.425657 Worker 3 finished
2025/04/28 19:11:50.675097 Worker 8: Finished validating randomizedcoder/docker-go-nix-simple-scratch-none-upx:1.0.0 (Overall Success: true, Duration: 18.291035743s)
2025/04/28 19:11:50.675110 Worker 8 finished
2025/04/28 19:11:50.675121 --- Validation Summary ---
2025/04/28 19:11:50.675124 Image Tag                                                                        Log      Metric   Duration           Overall Error
2025/04/28 19:11:50.675128 ------------------------------------------------------------------------------------------------------------------------
2025/04/28 19:11:50.675131 randomizedcoder/nix-go-nix-simple-distroless-gomod2nix-noupx:1.0.0               PASS     PASS     17.987s
2025/04/28 19:11:50.675133 randomizedcoder/nix-go-nix-simple-scratch-buildgomodule-noupx:1.0.0              PASS     PASS     18.013s
2025/04/28 19:11:50.675136 randomizedcoder/nix-go-nix-simple-distroless-gomod2nix-upx:1.0.0                 PASS     PASS     18.398s
2025/04/28 19:11:50.675139 randomizedcoder/nix-go-nix-simple-scratch-gomod2nix-noupx:1.0.0                  PASS     PASS     18.441s
2025/04/28 19:11:50.675142 randomizedcoder/nix-go-nix-simple-scratch-buildgomodule-upx:1.0.0                PASS     PASS     18.479s
2025/04/28 19:11:50.675144 randomizedcoder/nix-go-nix-simple-scratch-gomod2nix-upx:1.0.0                    PASS     PASS     18.497s
2025/04/28 19:11:50.675146 randomizedcoder/nix-go-nix-simple-distroless-buildgomodule-upx:1.0.0             PASS     PASS     18.552s
2025/04/28 19:11:50.675149 randomizedcoder/nix-go-nix-simple-distroless-buildgomodule-noupx:1.0.0           PASS     PASS     18.759s
2025/04/28 19:11:50.675151 randomizedcoder/docker-go-nix-simple-distroless-none-noupx:1.0.0                 PASS     PASS     17.769s
2025/04/28 19:11:50.675153 randomizedcoder/docker-go-nix-simple-distroless-docker-noupx:1.0.0               PASS     PASS     18.39s
2025/04/28 19:11:50.675172 randomizedcoder/docker-go-nix-simple-distroless-docker-upx:1.0.0                 PASS     PASS     18.414s
2025/04/28 19:11:50.675174 randomizedcoder/docker-go-nix-simple-distroless-athens-noupx:1.0.0               PASS     PASS     18.056s
2025/04/28 19:11:50.675177 randomizedcoder/docker-go-nix-simple-distroless-http-noupx:1.0.0                 PASS     PASS     18.181s
2025/04/28 19:11:50.675180 randomizedcoder/docker-go-nix-simple-distroless-athens-upx:1.0.0                 PASS     PASS     18.262s
2025/04/28 19:11:50.675182 randomizedcoder/docker-go-nix-simple-distroless-http-upx:1.0.0                   PASS     PASS     18.554s
2025/04/28 19:11:50.675184 randomizedcoder/docker-go-nix-simple-distroless-none-upx:1.0.0                   PASS     PASS     18.351s
2025/04/28 19:11:50.675186 randomizedcoder/docker-go-nix-simple-scratch-athens-noupx:1.0.0                  PASS     PASS     17.999s
2025/04/28 19:11:50.675188 randomizedcoder/docker-go-nix-simple-scratch-docker-noupx:1.0.0                  PASS     PASS     18.155s
2025/04/28 19:11:50.675193 randomizedcoder/docker-go-nix-simple-scratch-http-noupx:1.0.0                    PASS     PASS     17.837s
2025/04/28 19:11:50.675195 randomizedcoder/docker-go-nix-simple-scratch-docker-upx:1.0.0                    PASS     PASS     18.47s
2025/04/28 19:11:50.675197 randomizedcoder/docker-go-nix-simple-scratch-athens-upx:1.0.0                    PASS     PASS     18.421s
2025/04/28 19:11:50.675199 randomizedcoder/docker-go-nix-simple-scratch-none-noupx:1.0.0                    PASS     PASS     17.849s
2025/04/28 19:11:50.675202 randomizedcoder/docker-go-nix-simple-scratch-http-upx:1.0.0                      PASS     PASS     18.448s
2025/04/28 19:11:50.675204 randomizedcoder/docker-go-nix-simple-scratch-none-upx:1.0.0                      PASS     PASS     18.291s
2025/04/28 19:11:50.675206 ------------------------------------------------------------------------------------------------------------------------
2025/04/28 19:11:50.675208 Total Images: 24 | Total Checks: 48 | Passed Checks: 48 | Failed Checks: 0
2025/04/28 19:11:50.675211 Total Validation Duration: 55s
2025/04/28 19:11:50.675213 --------------------------
2025/04/28 19:11:50.675216
All image validations passed.
```


## Building all the container (make)

Running make will build the continers all the different ways, show you the time, and the size.

```
make deploy_athens   <--- Start Athens proxy cache for go
make squid           <--- Start squid
make
```

```
 => => naming to docker.io/randomizedcoder/docker-go-nix-simple-scratch-none-upx:1.0.0                                                                                                                                                                                       0.0s
 => => naming to docker.io/randomizedcoder/docker-go-nix-simple-scratch-none-upx:latest                                                                                                                                                                                      0.0s
[2025-04-28 11:33:57.978] Finished build-image-docker-scratch-none-upx. Duration: 32083 ms.
[2025-04-28 11:33:57.981] Collecting metrics for randomizedcoder/docker-go-nix-simple-scratch-none-upx:1.0.0...
[2025-04-28 11:33:58.028] Metrics saved to ./output/20250428_112359/build-image-docker-scratch-none-upx.csv
./scripts/generate_summary.sh
DEBUG: Phase 1 - Found latest output directory: './output/20250428_112359'
DEBUG: Phase 2 - Searching for 'build-*.csv' files in './output/20250428_112359'
DEBUG: Phase 2 - Found 24 metric file(s):
  './output/20250428_112359/build-image-docker-distroless-athens-noupx.csv'
  './output/20250428_112359/build-image-docker-distroless-athens-upx.csv'
  './output/20250428_112359/build-image-docker-distroless-docker-noupx.csv'
  './output/20250428_112359/build-image-docker-distroless-docker-upx.csv'
  './output/20250428_112359/build-image-docker-distroless-http-noupx.csv'
  './output/20250428_112359/build-image-docker-distroless-http-upx.csv'
  './output/20250428_112359/build-image-docker-distroless-none-noupx.csv'
  './output/20250428_112359/build-image-docker-distroless-none-upx.csv'
  './output/20250428_112359/build-image-docker-scratch-athens-noupx.csv'
  './output/20250428_112359/build-image-docker-scratch-athens-upx.csv'
  './output/20250428_112359/build-image-docker-scratch-docker-noupx.csv'
  './output/20250428_112359/build-image-docker-scratch-docker-upx.csv'
  './output/20250428_112359/build-image-docker-scratch-http-noupx.csv'
  './output/20250428_112359/build-image-docker-scratch-http-upx.csv'
  './output/20250428_112359/build-image-docker-scratch-none-noupx.csv'
  './output/20250428_112359/build-image-docker-scratch-none-upx.csv'
  './output/20250428_112359/build-image-nix-distroless-buildgomodule-noupx.csv'
  './output/20250428_112359/build-image-nix-distroless-buildgomodule-upx.csv'
  './output/20250428_112359/build-image-nix-distroless-gomod2nix-noupx.csv'
  './output/20250428_112359/build-image-nix-distroless-gomod2nix-upx.csv'
  './output/20250428_112359/build-image-nix-scratch-buildgomodule-noupx.csv'
  './output/20250428_112359/build-image-nix-scratch-buildgomodule-upx.csv'
  './output/20250428_112359/build-image-nix-scratch-gomod2nix-noupx.csv'
  './output/20250428_112359/build-image-nix-scratch-gomod2nix-upx.csv'
=============================================================================================
Build Summary - From Directory: ./output/20250428_112359
=============================================================================================
Target                                                      | Time (ms) | Size (MB) | Layers
------------------------------------------------------------|-----------|-----------|--------
build-image-docker-distroless-athens-noupx                  |     35101 |     15.22 |     12
build-image-docker-distroless-athens-upx                    |     38841 |      5.87 |     12
build-image-docker-distroless-docker-noupx                  |      2213 |     15.22 |     12
build-image-docker-distroless-docker-upx                    |      2075 |      5.87 |     12
build-image-docker-distroless-http-noupx                    |     32713 |     15.22 |     12
build-image-docker-distroless-http-upx                      |     36895 |      5.87 |     12
build-image-docker-distroless-none-noupx                    |     27626 |     15.22 |     12
build-image-docker-distroless-none-upx                      |     35659 |      5.87 |     12
build-image-docker-scratch-athens-noupx                     |     29616 |     13.52 |      1
build-image-docker-scratch-athens-upx                       |     29459 |      4.18 |      1
build-image-docker-scratch-docker-noupx                     |      2452 |     13.52 |      1
build-image-docker-scratch-docker-upx                       |      2378 |      4.18 |      1
build-image-docker-scratch-http-noupx                       |     37161 |     13.52 |      1
build-image-docker-scratch-http-upx                         |     31447 |      4.18 |      1
build-image-docker-scratch-none-noupx                       |     31228 |     13.52 |      1
build-image-docker-scratch-none-upx                         |     32083 |      4.18 |      1
build-image-nix-distroless-buildgomodule-noupx              |     55890 |     17.68 |     18
build-image-nix-distroless-buildgomodule-upx                |     15613 |      5.87 |     15
build-image-nix-distroless-gomod2nix-noupx                  |     63098 |     29.08 |     18
build-image-nix-distroless-gomod2nix-upx                    |     18871 |      5.69 |     15
build-image-nix-scratch-buildgomodule-noupx                 |      8725 |     15.78 |      7
build-image-nix-scratch-buildgomodule-upx                   |      8213 |      3.97 |      4
build-image-nix-scratch-gomod2nix-noupx                     |      9110 |     27.18 |      7
build-image-nix-scratch-gomod2nix-upx                       |      8229 |      3.79 |      4
=============================================================================================

INFO: Summary saved to ./output/20250428_112359/summary.txt
```

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

Athens usues
https://github.com/krallin/tini
https://github.com/gomods/athens/issues/1155
https://github.com/golang/go/issues/23705

## netGo && osusergo
Disabling cgo should results in -tags=netgo
```
The decision can also be forced while building the Go source tree by setting the netgo or netcgo build tag. The netgo build tag disables entirely the use of the native (CGO) resolver, meaning the Go resolver is the only one that can be used. With the netcgo build tag the native and the pure Go resolver are compiled into the binary, but the native (CGO) resolver is preferred over the Go resolver. With netcgo, the Go resolver can still be forced at runtime with GODEBUG=netdns=go.
```
https://pkg.go.dev/net


And disabling cgo will
```
When cgo is available, and the required routines are implemented in libc for a particular platform, cgo-based (libc-backed) code is used. This can be overridden by using osusergo build tag, which enforces the pure Go implementation.
```
https://pkg.go.dev/os/user#pkg-overview

```
// initConfVal initializes confVal based on the environment
// that will not change during program execution.
func initConfVal() {
	dnsMode, debugLevel := goDebugNetDNS()
	confVal.netGo = netGoBuildTag || dnsMode == "go"
	confVal.netCgo = netCgoBuildTag || dnsMode == "cgo"
	confVal.dnsDebugLevel = debugLevel

	if confVal.dnsDebugLevel > 0 {
		defer func() {
			if confVal.dnsDebugLevel > 1 {
				println("go package net: confVal.netCgo =", confVal.netCgo, " netGo =", confVal.netGo)
			}
			if dnsMode != "go" && dnsMode != "cgo" && dnsMode != "" {
				println("go package net: GODEBUG=netdns contains an invalid dns mode, ignoring it")
			}
			switch {
			case netGoBuildTag || !cgoAvailable:
				if dnsMode == "cgo" {
					println("go package net: ignoring GODEBUG=netdns=cgo as the binary was compiled without support for the cgo resolver")
				} else {
					println("go package net: using the Go DNS resolver")
				}
			case netCgoBuildTag:
				if dnsMode == "go" {
					println("go package net: GODEBUG setting forcing use of the Go resolver")
				} else {
					println("go package net: using the cgo DNS resolver")
				}
			default:
				if dnsMode == "go" {
					println("go package net: GODEBUG setting forcing use of the Go resolver")
				} else if dnsMode == "cgo" {
					println("go package net: GODEBUG setting forcing use of the cgo resolver")
				} else {
					println("go package net: dynamic selection of DNS resolver")
				}
			}
		}()
	}
```
https://cs.opensource.google/go/go/+/master:src/net/conf.go;l=85?q=netgo&ss=go%2Fgo


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

## Small golang containers

https://github.com/Snawoot/opera-proxy/blob/master/Dockerfile

https://laurentsv.com/blog/2024/06/25/stop-the-go-and-docker-madness.html

## UPX Shrinker

https://upx.github.io/
https://sourceforge.net/projects/upx/
https://words.filippo.io/shrink-your-go-binaries-with-this-one-weird-trick/

## Nix and Bazel

https://youtu.be/2wI5J8XYxM8?si=bOdpb6sL_OUUuId8