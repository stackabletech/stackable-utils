{ pkgs ? import <nixpkgs> { } }:
pkgs.mkShell {
  nativeBuildInputs = with pkgs; [
    cargo-edit
    gettext # envsubst
    gh
    yq-go
  ];
}
