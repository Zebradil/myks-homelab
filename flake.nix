{
  description = "required tools";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs =
    { nixpkgs, ... }:
    let
      supportedSystems = [
        "aarch64-darwin"
        "x86_64-linux"
      ];
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;
      pkgsFor = system: import nixpkgs { inherit system; };
    in
    {
      formatter = forAllSystems (system: (pkgsFor system).nixfmt-tree);
      devShells = forAllSystems (system: {
        default = (pkgsFor system).mkShell {
          packages = with (pkgsFor system); [
            jq
            mise
          ];
          shellHook = ''
            git config core.hooksPath hooks

            mise install
            if [[ $(mise doctor --json | jq ".activated") != "true" ]]; then
              source <(mise activate)
            fi
          '';
        };
      });
    };
}
