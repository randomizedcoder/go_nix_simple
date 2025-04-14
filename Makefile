
all:

build_simple:
	nix build .#go-nix-simple

docker:
	nix build .

docker_trace:
	nix build . --show-trace

load:
	docker load < result

run:
	docker run -d -p 9108:9108 go-nix-simple:latest

curl:
	curl http://localhost:9108/metrics

# end
