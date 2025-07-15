{
  description = "required tools";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    myks.url = "github:mykso/myks";
  };

  outputs =
    { ... }@inputs:
    inputs.flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import inputs.nixpkgs {
          inherit system;
          overlays = [
            (final: _prev: {
              myks = inputs.myks.packages.${final.system}.default;
            })
          ];
        };
      in
      {
        devShells.default = pkgs.mkShell {
          packages = with pkgs; [
            go-task
            kubeconform
            kubernetes-helm
            myks
            sops
          ];
        };
      }
    );
}
