#
# /cmd/generate-containerfiles/Makefile
#

# ldflags variables to update --version
COMMIT := $(shell git describe --always)
DATE := $(shell date -u +"%Y-%m-%d-%H:%M")
VERSION := $(shell cat ../../VERSION)
BINARY := generate-containerfiles

# Define ldflags string once
LDFLAGS_STR := "-X main.commit=${COMMIT} -X main.date=${DATE} -X main.version=${VERSION}"

.PHONY: all clean build test

all: build

test:
	go test

clean:
	rm -f ./${BINARY}

build:
	go build -ldflags ${LDFLAGS_STR} -o ./${BINARY} ./${BINARY}.go

# Optional: Clearer name if keeping the Athens build variant
# build-athens:
#	GOPROXY=http://127.0.0.1:8888 \
#	go build -ldflags ${LDFLAGS_STR} -o ./${BINARY} ./${BINARY}.go

# end