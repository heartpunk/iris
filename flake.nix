{
  description = "Iris — formally-specified terminal multiplexer in Idris 2";

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

      mkNativeSupport = system:
        let
          pkgs = import nixpkgs { inherit system; };
        in
        pkgs.rustPlatform.buildRustPackage {
          pname = "iris-native-support";
          version = "0.1.0";
          src = ./iris-native/support;
          cargoLock.lockFile = ./iris-native/support/Cargo.lock;
        };

      mkIris = system:
        let
          pkgs = import nixpkgs { inherit system; };
          idris2Version = pkgs.idris2.version;
          nativeSupport = mkNativeSupport system;
        in
        pkgs.stdenv.mkDerivation {
          pname = "iris";
          version = "0.1.0";
          src = ./.;
          nativeBuildInputs = [ pkgs.idris2 pkgs.makeWrapper ];
          buildInputs = [ nativeSupport ];
          buildPhase = ''
            export IDRIS2_PREFIX=$TMPDIR/.idris2
            export IDRIS2_PACKAGE_PATH=$TMPDIR/.idris2/idris2-${idris2Version}

            # Foundation: iris-core
            idris2 --build iris-core/iris-core.ipkg
            idris2 --install iris-core/iris-core.ipkg

            # Phase 1 backend: iris-tmux
            idris2 --build iris-tmux/iris-tmux.ipkg
            idris2 --install iris-tmux/iris-tmux.ipkg

            # Phase 2 backend: iris-native (Rust FFI support lib required)
            export IDRIS2_LDFLAGS="-L${nativeSupport}/lib"
            idris2 --build iris-native/iris-native.ipkg
            idris2 --install iris-native/iris-native.ipkg
            unset IDRIS2_LDFLAGS

            # Tools: iris-rec, iris-replay
            idris2 --build iris-rec/iris-rec.ipkg
            idris2 --install iris-rec/iris-rec.ipkg
            idris2 --build iris-replay/iris-replay.ipkg
            idris2 --install iris-replay/iris-replay.ipkg

            # Test executables
            idris2 --build tests/iris-tmux-tests.ipkg
            idris2 --build tests/tests.ipkg
          '';
          installPhase = ''
            mkdir -p $out/bin $out/lib $out/share/iris

            # Rust FFI support library
            cp -r ${nativeSupport}/lib/* $out/lib/

            # iris-native executable
            cp -r iris-native/build/exec/iris-native_app $out/bin/
            cp iris-native/build/exec/iris-native $out/bin/iris-native-unwrapped
            makeWrapper $out/bin/iris-native-unwrapped $out/bin/iris-native \
              --prefix PATH : ${pkgs.lib.makeBinPath [ pkgs.coreutils ]} \
              --prefix DYLD_LIBRARY_PATH : $out/lib \
              --prefix LD_LIBRARY_PATH : $out/lib

            # iris-rec executable
            cp -r iris-rec/build/exec/iris-rec_app $out/bin/
            cp iris-rec/build/exec/iris-rec $out/bin/iris-rec-unwrapped
            makeWrapper $out/bin/iris-rec-unwrapped $out/bin/iris-rec \
              --prefix PATH : ${pkgs.lib.makeBinPath [ pkgs.coreutils ]}

            # iris-replay executable
            cp -r iris-replay/build/exec/iris-replay_app $out/bin/
            cp iris-replay/build/exec/iris-replay $out/bin/iris-replay-unwrapped
            makeWrapper $out/bin/iris-replay-unwrapped $out/bin/iris-replay \
              --prefix PATH : ${pkgs.lib.makeBinPath [ pkgs.coreutils ]}

            # iris-tmux-tests executable
            cp -r tests/build/exec/iris-tmux-tests_app $out/bin/
            cp tests/build/exec/iris-tmux-tests $out/bin/iris-tmux-tests-unwrapped
            makeWrapper $out/bin/iris-tmux-tests-unwrapped $out/bin/iris-tmux-tests \
              --prefix PATH : ${pkgs.lib.makeBinPath [ pkgs.coreutils ]}

            # iris-tests executable
            cp -r tests/build/exec/iris-tests_app $out/bin/
            cp tests/build/exec/iris-tests $out/bin/iris-tests-unwrapped
            makeWrapper $out/bin/iris-tests-unwrapped $out/bin/iris-tests \
              --prefix PATH : ${pkgs.lib.makeBinPath [ pkgs.coreutils ]}

            # Test fixtures
            cp -r tests/fixtures $out/share/iris/
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
        default = mkIris system;
      });

      checks = forLinuxSystems (system:
        let
          pkgs = import nixpkgs { inherit system; };
          irisPkg = mkIris system;
        in
        {
          integration = pkgs.testers.nixosTest {
            name = "iris-tmux-integration";
            nodes.machine = { ... }: {
              environment.systemPackages = [
                irisPkg
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
