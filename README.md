# go_nix_simple

example of a go program built into a nix container

see the Makefile for how to run this

```
[das@t:~/Downloads/go_nix_simple]$ docker image ls go-nix-simple
REPOSITORY      TAG       IMAGE ID       CREATED        SIZE
go-nix-simple   latest    f1ab995eff6f   55 years ago   44.3MB
```

## Layer 1/9 libunistring
<img src="docs/images/Screenshot From 2025-04-14 15-30-18.png" alt="Layer 1/9 libunistring" width="90%">

## Layer 4/9 libgcc
<img src="docs/images/Screenshot From 2025-04-14 15-31-26.png" alt="Layer 4/9 libgcc" width="90%">

## Layer 9/9 go_nix_simple
<img src="docs/images/Screenshot From 2025-04-14 15-33-40.png" alt="Layer 9/9 go_nix_simple" width="90%">
