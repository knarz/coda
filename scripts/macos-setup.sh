#!/bin/bash
set -x #echo on
set -eu

USAGE="$0 <download|compile|all>"

if [[ $# -eq 0 ]]; then
  echo $USAGE
  exit 1
fi

case $1 in
  "download")
    DOWNLOAD_THINGS=YES
    COMPILE_THINGS=NO ;;
  "compile")
    DOWNLOAD_THINGS=NO
    COMPILE_THINGS=YES ;;
  "all")
    DOWNLOAD_THINGS=YES
    COMPILE_THINGS=YES ;;
  *)
    echo $USAGE
    exit 1
esac

if [[ $DOWNLOAD_THINGS == "YES" ]]; then
  PACKAGES="gpatch opam cmake gmp pkg-config openssl libffi libsodium boost zlib libomp"

  # removing already installed packages from the list
  for p in $(env HOMEBREW_NO_AUTO_UPDATE=1 brew list); do
    PACKAGES=${PACKAGES//$p/}
  done;

  # only run if there's work to do
  if [[ $PACKAGES = *[![:space:]]* ]]; then
    yes | env HOMEBREW_NO_AUTO_UPDATE=1 brew install $PACKAGES
  else
    echo 'All brew packages have already been installed.'
  fi

  # ocaml downloading
  OPAMYES=1 opam init
  eval $(opam config env)
else
  echo 'Not running download step'
fi


# Compile things
if [[ $COMPILE_THINGS == "YES" ]]; then
  opam update
  # This is dirty, keep the OCaml project version up to date!
  opam switch create 4.07.1 || true 
  opam switch 4.07.1
  # All our ocaml packages
  env TERM=xterm opam switch -y import src/opam.export
  eval $(opam config env)

  # Extlib gets automatically installed, but we want our pin, so we should
  # uninstall here
  opam uninstall -y extlib

  # Our pins
  env TERM=xterm opam pin -y add src/external/ocaml-sodium
  env TERM=xterm opam pin -y add src/external/rpc_parallel
  env TERM=xterm opam pin -y add src/external/ocaml-extlib
  env TERM=xterm opam pin -y add src/external/digestif
  env TERM=xterm opam pin -y add src/external/async_kernel
  env TERM=xterm opam pin -y add src/external/coda_base58
  env TERM=xterm opam pin -y add src/external/graphql_ppx
  eval $(opam config env)

  # Kademlia
  curl https://nixos.org/nix/install | sh
  touch ~/.profile
  set +u
  . ~/.nix-profile/etc/profile.d/nix.sh
  if [[ "$CIRCLE_BUILD_NUM" ]]; then
      mkdir -p ~/.config/nix
      cat > ~/.config/nix/nix.conf <<EOF
substituters = https://cache.nixos.org s3://o1-nix-cache
# Checking signatures is broken with S3 based Nix caches, see
# https://github.com/NixOS/nix/issues/2024
require-sigs = false
EOF
  fi
  set +e
  nix-build --dry-run src/app/kademlia-haskell/release2.nix 2>&1 | grep -q 'these derivations will be built'
  building_kad=$?
  set -e
  make kademlia
  if [[ "$CIRCLE_BUILD_NUM" && "$building_kad" = 0 ]]; then
      nix copy --to s3://o1-nix-cache src/app/kademlia-haskell/result/
      # Incantation to copy build dependencies. We instantiate the nix
      # expression to a derivation, get a list of the derivations it references,
      # and copy the outputs of those derivations to our cache.
      nix copy --to s3://o1-nix-cache $(nix-store -r $(nix-store -q --references $(nix-instantiate src/app/kademlia-haskell/release2.nix)))
  fi
  set -u
else
  echo 'Not running compile step.'
fi
