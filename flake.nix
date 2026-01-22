{
  description = "Development environment for a Pi Pico W project";

  inputs = {
    nixpkgs-stable.url = "github:NixOS/nixpkgs/nixos-25.11";

    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = {
    self,
    nixpkgs-stable,
    nixpkgs-unstable,
    ...
  }: let
    system = "x86_64-linux";

    pkgs_stable = nixpkgs-stable.legacyPackages.${system};
    pkgs_unstable = nixpkgs-unstable.legacyPackages.${system};

    pkgs_stable_configured = import nixpkgs-stable {
      inherit system;
      config = {
        allowUnfree = true;
      };
    };
    pkgs_unstable_configured = import nixpkgs-unstable {
      inherit system;
      config = {
        allowUnfree = true;
      };
    };

    full_pico_sdk =
      pkgs_stable_configured.pico-sdk.override
      {
        withSubmodules = true;
      };

    deps = with pkgs_stable_configured; [
      gcc-arm-embedded
      full_pico_sdk
      picotool
      gdb
      cmake
      udisks
      python3
      openocd
      ninja
      clang
      entr
      shfmt
      zig
    ];

    libusbLibPath = "${pkgs_stable_configured.libusb1}/lib";
    picoSdkPath = "${full_pico_sdk}/lib/pico-sdk";
  in {
    devShells.${system}.default = pkgs_stable.mkShell {
      nativeBuildInputs = deps;

      shellHook = ''
        export PICO_SDK_PATH="${picoSdkPath}"
      '';
    };
  };
}
