{
  pkgs, lib,
  ...
} @ inputs :
let
  np-params = rec {
    github-repo = "DavHau/nix-portable";
    github-url = "https://github.com/${github-repo}";
    binary-url = "${github-url}/releases/download/v009/nix-portable-aarch64-linux";
  };
  bootstrap = pkgs.fetchurl {
    url = np-params.binary-url;
    hash = "sha256-XVGsNM7PNCLEQK+Itu8LFMxzWvZYfpU7OGIqnfBioXQ=";
    downloadToTemp = true;
    executable = true;
    postFetch = ''
      mkdir -p ''$out/bin
      mv ''$downloadedFile ''$out/bin/nix-portable
    '';
  };
in {
  inherit bootstrap;
}
