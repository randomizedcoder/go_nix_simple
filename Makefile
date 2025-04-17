#
# /go-nix-simple/Makefile
#

VERSION := $(shell cat VERSION)
LOCAL_MAJOR_VERSION := $(word 1,$(subst ., ,$(VERSION)))
LOCAL_MINOR_VERSION := $(word 2,$(subst ., ,$(VERSION)))
LOCAL_PATCH_VERSION := $(word 3,$(subst ., ,$(VERSION)))
SHELL := /usr/bin/env bash
.SHELLFLAGS := -eu -o pipefail -c

MYPATH = $(shell pwd)
COMMIT := $(shell git describe --always)
DATE := $(shell date -u +"%Y-%m-%d-%H:%M")

TIMESTAMP := date +"%Y-%m-%d %H:%M:%S.%3N"

# Fake targets
.PHONY: all nix_build_go-nix-simple nix_build_docker nix_build_docker_scratch \
	nix_build_docker_trace nix_build_docker_load gomod2nix \
	nix_build_docker_gomod2nix nix_build_docker_gomod2nix_load \
	builddocker_go-nix-simple-distroless \
	builddocker_go-nix-simple-distroless-athens \
	builddocker_go-nix-simple-distroless-scratch \
	deploy_athens down_athens athens_traffic nix_build_athens run_athens ls \
	dive dive-distroless run run-distroless curl prepare clear_go_mod_cache \
	go_glean flake_metadata flake_show

all: nix_build_docker nix_build_docker_load \
	nix_build_docker_upx nix_build_docker_load \
	nix_build_docker_scratch nix_build_docker_load \
	builddocker_go-nix-simple-distroless \
	builddocker_go-nix-simple-distroless-athens \
	builddocker_go-nix-simple-scratch \
	builddocker_go-nix-simple-upx \
	gomod2nix \
	ls

#--------------------------
# nix build

nix_build_go-nix-simple:
	@_start_time_ns=$$(date +%s%N); \
	echo "[$($(TIMESTAMP))] Starting $@..."; \
	nix build .#go-nix-simple; \
	_end_time_ns=$$(date +%s%N); \
	_duration_ms=$$(( (_end_time_ns - _start_time_ns) / 1000000 )); \
	echo "[$($(TIMESTAMP))] Finished $@. Duration: $$_duration_ms ms."

nix_build_docker:
	@_start_time_ns=$$(date +%s%N); \
	echo "[$($(TIMESTAMP))] Starting $@..."; \
	nix build .; \
	_end_time_ns=$$(date +%s%N); \
	_duration_ms=$$(( (_end_time_ns - _start_time_ns) / 1000000 )); \
	echo "[$($(TIMESTAMP))] Finished $@. Duration: $$_duration_ms ms."

nix_build_docker_upx:
	@_start_time_ns=$$(date +%s%N); \
	echo "[$($(TIMESTAMP))] Starting $@..."; \
	nix build .#docker-image-upx; \
	_end_time_ns=$$(date +%s%N); \
	_duration_ms=$$(( (_end_time_ns - _start_time_ns) / 1000000 )); \
	echo "[$($(TIMESTAMP))] Finished $@. Duration: $$_duration_ms ms."

nix_build_docker_scratch:
	@_start_time_ns=$$(date +%s%N); \
	echo "[$($(TIMESTAMP))] Starting $@..."; \
	nix build .#docker-image-scratch; \
	_end_time_ns=$$(date +%s%N); \
	_duration_ms=$$(( (_end_time_ns - _start_time_ns) / 1000000 )); \
	echo "[$($(TIMESTAMP))] Finished $@. Duration: $$_duration_ms ms."

nix_build_docker_trace:
	@_start_time_ns=$$(date +%s%N); \
	echo "[$($(TIMESTAMP))] Starting $@..."; \
	nix build . --show-trace; \
	_end_time_ns=$$(date +%s%N); \
	_duration_ms=$$(( (_end_time_ns - _start_time_ns) / 1000000 )); \
	echo "[$($(TIMESTAMP))] Finished $@. Duration: $$_duration_ms ms."

nix_build_docker_load:
	@_start_time_ns=$$(date +%s%N); \
	echo "[$($(TIMESTAMP))] Starting $@..."; \
	docker load < result; \
	_end_time_ns=$$(date +%s%N); \
	_duration_ms=$$(( (_end_time_ns - _start_time_ns) / 1000000 )); \
	echo "[$($(TIMESTAMP))] Finished $@. Duration: $$_duration_ms ms."

#---------
# gomod2nix
gomod2nix: nix_build_docker_gomod2nix nix_build_docker_gomod2nix_load

nix_build_docker_gomod2nix:
	@_start_time_ns=$$(date +%s%N); \
	echo "[$($(TIMESTAMP))] Starting $@..."; \
	nix build .#docker-image-gomod2nix; \
	_end_time_ns=$$(date +%s%N); \
	_duration_ms=$$(( (_end_time_ns - _start_time_ns) / 1000000 )); \
	echo "[$($(TIMESTAMP))] Finished $@. Duration: $$_duration_ms ms."

nix_build_docker_gomod2nix_load:
	@_start_time_ns=$$(date +%s%N); \
	echo "[$($(TIMESTAMP))] Starting $@..."; \
	docker load < result; \
	_end_time_ns=$$(date +%s%N); \
	_duration_ms=$$(( (_end_time_ns - _start_time_ns) / 1000000 )); \
	echo "[$($(TIMESTAMP))] Finished $@. Duration: $$_duration_ms ms."

#--------------------------
# docker build

builddocker_go-nix-simple-distroless:
	@_start_time_ns=$$(date +%s%N); \
	echo "[$($(TIMESTAMP))] Starting $@..."; \
	echo "================================"; \
	echo "Make builddocker_go_nix_simple randomizedcoder/go-nix-simple-distroless:${VERSION}"; \
	docker build \
		--network=host \
		--build-arg MYPATH=${MYPATH} \
		--build-arg COMMIT=${COMMIT} \
		--build-arg DATE=${DATE} \
		--build-arg VERSION=${VERSION} \
		--file build/containers/go_nix_simple/Containerfile \
		--tag randomizedcoder/docker-go-nix-simple-distroless:${VERSION} \
		--tag randomizedcoder/docker-go-nix-simple-distroless:latest \
		${MYPATH}; \
	_end_time_ns=$$(date +%s%N); \
	_duration_ms=$$(( (_end_time_ns - _start_time_ns) / 1000000 )); \
	echo "[$($(TIMESTAMP))] Finished $@. Duration: $$_duration_ms ms."

builddocker_go-nix-simple-distroless-athens:
	@_start_time_ns=$$(date +%s%N); \
	echo "[$($(TIMESTAMP))] Starting $@..."; \
	echo "================================"; \
	echo "Make builddocker_go_nix_simple randomizedcoder/go-nix-simple-distroless-athens:${VERSION}"; \
	docker build \
		--network=host \
		--build-arg MYPATH=${MYPATH} \
		--build-arg COMMIT=${COMMIT} \
		--build-arg DATE=${DATE} \
		--build-arg VERSION=${VERSION} \
		--file build/containers/go_nix_simple/Containerfile_athens \
		--tag randomizedcoder/docker-go-nix-simple-distroless-athens:${VERSION} \
		--tag randomizedcoder/docker-go-nix-simple-distroless-athens:latest \
		${MYPATH}; \
	_end_time_ns=$$(date +%s%N); \
	_duration_ms=$$(( (_end_time_ns - _start_time_ns) / 1000000 )); \
	echo "[$($(TIMESTAMP))] Finished $@. Duration: $$_duration_ms ms."

builddocker_go-nix-simple-scratch:
	@_start_time_ns=$$(date +%s%N); \
	echo "[$($(TIMESTAMP))] Starting $@..."; \
	echo "================================"; \
	echo "Make builddocker_go_nix_simple randomizedcoder/docker-go-nix-simple-scratch:${VERSION}"; \
	docker build \
		--network=host \
		--build-arg MYPATH=${MYPATH} \
		--build-arg COMMIT=${COMMIT} \
		--build-arg DATE=${DATE} \
		--build-arg VERSION=${VERSION} \
		--file build/containers/go_nix_simple/Containerfile_scratch \
		--tag randomizedcoder/docker-go-nix-simple-scratch:${VERSION} \
		--tag randomizedcoder/docker-go-nix-simple-scratch:latest \
		${MYPATH}; \
	_end_time_ns=$$(date +%s%N); \
	_duration_ms=$$(( (_end_time_ns - _start_time_ns) / 1000000 )); \
	echo "[$($(TIMESTAMP))] Finished $@. Duration: $$_duration_ms ms."

builddocker_go-nix-simple-upx:
	@_start_time_ns=$$(date +%s%N); \
	echo "[$($(TIMESTAMP))] Starting $@..."; \
	echo "================================"; \
	echo "Make builddocker_go_nix_simple randomizedcoder/docker-go-nix-simple-upx:${VERSION}"; \
	docker build \
		--network=host \
		--build-arg MYPATH=${MYPATH} \
		--build-arg COMMIT=${COMMIT} \
		--build-arg DATE=${DATE} \
		--build-arg VERSION=${VERSION} \
		--file build/containers/go_nix_simple/Containerfile_upx \
		--tag randomizedcoder/docker-go-nix-simple-scratch-upx:${VERSION} \
		--tag randomizedcoder/docker-go-nix-simple-scratch-upx:latest \
		${MYPATH}; \
	_end_time_ns=$$(date +%s%N); \
	_duration_ms=$$(( (_end_time_ns - _start_time_ns) / 1000000 )); \
	echo "[$($(TIMESTAMP))] Finished $@. Duration: $$_duration_ms ms."
# --progress=plain \

#--------------------------
# docker compose athens

# https://docs.docker.com/engine/reference/commandline/docker/
# https://docs.docker.com/compose/reference/
deploy_athens:
	@echo "================================"
	@echo "Make deploy_athens"
	docker compose \
		--file build/containers/athens/docker-compose-athens.yml \
		up -d --remove-orphans

down_athens:
	@echo "================================"
	@echo "Make down_athens"
	docker compose \
		--file build/containers/athens/docker-compose-athens.yml \
		down

athens_traffic:
	sudo tcpdump -ni any port 8888

#--------------------------
# nix build athens docker container

nix_build_athens:
	nix build .#athens-nix-image
	docker load < result

run_athens:
	docker run -d -p 8888:8888 randomizedcoder/athens-nix:latest

#--------------------------
# inspect

ls:
	docker image ls randomizedcoder/nix-go-nix-simple-distroless;
	docker image ls randomizedcoder/nix-go-nix-simple-scratch;
	docker image ls randomizedcoder/gomod2nix-go-nix-simple-scratch
	docker image ls randomizedcoder/docker-go-nix-simple-distroless;
	docker image ls randomizedcoder/docker-go-nix-simple-distroless-athens;
	docker image ls randomizedcoder/docker-go-nix-simple-distroless-scratch;
	docker image ls randomizedcoder/gomod2nix-go-nix-simple-scratch;
	@echo "===="
	docker image ls | grep go-nix-simple

dive:
	dive randomizedcoder/go-nix-simple:latest

dive-distroless:
	dive randomizedcoder/go-nix-simple-distroless:latest

run:
	docker run -d -p 9108:9108 randomizedcoder/go-nix-simple:latest

run-distroless:
	docker run -d -p 9108:9108 randomizedcoder/go-nix-simple-distroless:latest

curl:
	curl http://localhost:9108/metrics

# https://ryantm.github.io/nixpkgs/builders/images/dockertools/#ssec-pkgs-dockerTools-fetchFromRegistry
# https://github.com/NixOS/nixpkgs/blob/master/pkgs/build-support/docker/nix-prefetch-docker
prepare:
	nix-shell -p nix-prefetch-docker
	nix-prefetch-docker --image-name gcr.io/distroless/static-debian12 --image-tag latest

#--------------------------
# clear go mod cache

clear_go_mod_cache:
	sudo rm -rf /home/das/go/pkg/mod/

go_glean:
	go clean -modcache

#--------------------------
# flake commands

flake_metadata:
	nix flake metadata

flake_show:
	nix flake show

# end
