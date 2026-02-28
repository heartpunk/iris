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

      mkCompressPkg = system:
        let
          pkgs = import nixpkgs { inherit system; };
          rustPlatform = pkgs.rustPlatform;
          supportLib = rustPlatform.buildRustPackage {
            pname = "iris-compress-support";
            version = "0.1.0";
            src = ./iris-compress/support;
            cargoLock.lockFile = ./iris-compress/support/Cargo.lock;
          };
          dylibExt = if pkgs.stdenv.isDarwin then "dylib" else "so";
        in
        pkgs.stdenv.mkDerivation {
          pname = "iris-compress";
          version = "0.1.0";
          src = ./.;
          nativeBuildInputs = [ pkgs.idris2 pkgs.makeWrapper ];
          buildInputs = [ supportLib ];
          buildPhase = ''
            # Install iris-core
            IDRIS2_PREFIX=$TMPDIR/.idris2 idris2 --install iris-core/iris-core.ipkg
            # Build iris-compress
            cd iris-compress
            IDRIS2_PACKAGE_PATH=$TMPDIR/.idris2/idris2-${pkgs.idris2.version} idris2 --build iris-compress.ipkg
            # Copy support library into app dir
            cp ${supportLib}/lib/libiris_compress_support.${dylibExt} build/exec/iris-compress_app/
            cd ..
          '';
          installPhase = ''
            mkdir -p $out/bin
            cp -r iris-compress/build/exec/iris-compress_app $out/bin/
            cp iris-compress/build/exec/iris-compress $out/bin/iris-compress-unwrapped
            makeWrapper $out/bin/iris-compress-unwrapped $out/bin/iris-compress \
              --prefix PATH : ${pkgs.lib.makeBinPath [ pkgs.lzip pkgs.zstd ]}
          '';
        };

      mkCompressTestPkg = system:
        let
          pkgs = import nixpkgs { inherit system; };
        in
        pkgs.stdenv.mkDerivation {
          pname = "iris-compress-tests";
          version = "0.1.0";
          src = ./.;
          nativeBuildInputs = [ pkgs.idris2 ];
          buildPhase = ''
            # Install iris-core
            IDRIS2_PREFIX=$TMPDIR/.idris2 idris2 --install iris-core/iris-core.ipkg
            # Install iris-compress
            IDRIS2_PACKAGE_PATH=$TMPDIR/.idris2/idris2-${pkgs.idris2.version} \
              IDRIS2_PREFIX=$TMPDIR/.idris2 idris2 --install iris-compress/iris-compress.ipkg
            # Build compress-tests
            cd tests
            IDRIS2_PACKAGE_PATH=$TMPDIR/.idris2/idris2-${pkgs.idris2.version} idris2 --build compress-tests.ipkg
            cd ..
          '';
          installPhase = ''
            mkdir -p $out/bin
            cp -r tests/build/exec/compress-tests_app $out/bin/
            cp tests/build/exec/compress-tests $out/bin/
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
              pkgs.zstd
            ];
          };
        });

      packages = forAllSystems (system: {
        iris-tmux-tests = mkTestPkg system;
        iris-compress = mkCompressPkg system;
        iris-compress-tests = mkCompressTestPkg system;
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
