# This might be helfpul later:
# https://www.reddit.com/r/NixOS/comments/6hswg4/how_do_i_turn_an_overlay_into_a_proper_package_set/
self: super:

let
  inherit (super) lib stdenv fetchFromGitHub callPackage;
  overlayOcamlPackages =
    import ./ocaml/overlay-ocaml-packages.nix {
      inherit lib callPackage;
    };

in

(overlayOcamlPackages [ (callPackage ./ocaml { }) ] self super) // {
  # Stripped down postgres without the `bin` part, to allow static linking
  # with musl
  libpq = super.postgresql.override { enableSystemd = false; gssSupport = false; };

  opaline = (super.opaline.override {
    inherit (self) ocamlPackages;
  });
  esy = callPackage ./ocaml/esy { };

  pkgsStatic = super.pkgsStatic.appendOverlays (callPackage ./static { });

  pkgsCross =
    let
      static-overlays = callPackage ./static { };
      cross-overlays = callPackage ./cross { };
    in
    super.pkgsCross // {

      musl64 = super.pkgsCross.musl64.appendOverlays static-overlays;

      aarch64-multiplatform =
        super.pkgsCross.aarch64-multiplatform.appendOverlays
          cross-overlays;

      aarch64-multiplatform-musl =
        (super.pkgsCross.aarch64-multiplatform-musl.appendOverlays
          (cross-overlays ++ static-overlays));
    };

  # Other packages

  lib = lib.fix (self: lib //
  (import
    (builtins.fetchTarball {
      url = https://github.com/hercules-ci/gitignore.nix/archive/5b9e0ff9d3b551234b4f3eb3983744fa354b17f1.tar.gz;
      sha256 = "01l4phiqgw9xgaxr6jr456qmww6kzghqrnbc7aiiww3h6db5vw53";
    })
    { inherit lib; }) // {
    filterSource = { src, dirs ? [ ], files ? [ ] }: (self.cleanSourceWith {
      inherit src;
      # Good examples: https://github.com/NixOS/nixpkgs/blob/master/lib/sources.nix
      filter = name: type:
        let
          path = toString name;
          baseName = baseNameOf path;
          relPath = self.removePrefix (toString src + "/") path;
        in
        self.any (dir: dir == relPath || (self.hasPrefix "${dir}/" relPath)) dirs ||
        (type == "regular" && (self.any (file: file == baseName) files));
    });

    filterGitSource = args: self.gitignoreSource (self.filterSource args);

    inherit overlayOcamlPackages;
  });

  inherit (callPackage ./cockroachdb { }) cockroachdb-21_1_x cockroachdb-21_2_x;
  cockroachdb = self.cockroachdb-21_1_x;
}
