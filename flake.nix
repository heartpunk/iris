{
  description = "Iris Idris 2 development environment";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs, ... }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
      linuxSystems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
      forLinuxSystems = nixpkgs.lib.genAttrs linuxSystems;

      mkTestPkg = system:
        let
          pkgs = import nixpkgs { inherit system; };
        in
        pkgs.stdenv.mkDerivation {
          pname = "iris-tmux-tests";
          version = "0.1.0";
          src = ./.;
          nativeBuildInputs = [ pkgs.idris2 pkgs.makeWrapper ];
          buildPhase = ''
            idris2 --build iris-tmux/iris-tmux.ipkg
            IDRIS2_PREFIX=$TMPDIR/.idris2 idris2 --install iris-tmux/iris-tmux.ipkg
            cd tests
            IDRIS2_PACKAGE_PATH=$TMPDIR/.idris2/idris2-${pkgs.idris2.version} idris2 --build iris-tmux-tests.ipkg
            cd ..
          '';
          installPhase = ''
            mkdir -p $out/bin $out/share/iris-tmux-tests
            cp -r tests/build/exec/iris-tmux-tests_app $out/bin/
            cp tests/build/exec/iris-tmux-tests $out/bin/iris-tmux-tests-unwrapped
            cp -r tests/fixtures $out/share/iris-tmux-tests/
            makeWrapper $out/bin/iris-tmux-tests-unwrapped $out/bin/iris-tmux-tests \
              --prefix PATH : ${pkgs.lib.makeBinPath [ pkgs.coreutils ]}
          '';
        };
    in
    {
      devShells = forAllSystems (system:
        let
          pkgs = import nixpkgs { inherit system; };
        in
        {
          default = pkgs.mkShell {
            packages = [
              pkgs.idris2
              pkgs."ovh-ttyrec"
              pkgs.ipbt
              pkgs.lzip
              pkgs.rustc
              pkgs.cargo
            ];
          };
        });

      packages = forAllSystems (system: {
        iris-tmux-tests = mkTestPkg system;
      });

      checks = forLinuxSystems (system:
        let
          pkgs = import nixpkgs { inherit system; };
          testPkg = mkTestPkg system;
        in
        {
          integration = pkgs.testers.nixosTest {
            name = "iris-tmux-integration";
            nodes.machine = { ... }: {
              environment.systemPackages = [
                testPkg
                pkgs.tmux
              ];
              environment.etc."iris-test-vm".text = "k7X9mQ2vL4pR8wF1nJ6bT3hY5dA0sG";
            };
            testScript = ''
              machine.start()
              machine.wait_for_unit("multi-user.target")
              machine.succeed("iris-tmux-tests integration")
            '';
          };
        });
    };
}
