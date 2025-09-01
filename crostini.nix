{ modulesPath, lib, pkgs, ... }:

let
  # Pin ChromiumOS guest tools (used for sommelier/garcon glue)
  cros-container-guest-tools-src-version =
    "2083eb893d0d2fbc90a413a9c08d8ee62fd7425a";

  cros-container-guest-tools-src = pkgs.fetchgit {
    url = "https://chromium.googlesource.com/chromiumos/containers/cros-container-guest-tools";
    rev = cros-container-guest-tools-src-version;
    outputHash = "sha256-hKJWq4xuipggdTM2BczzEm7PYrCTJiblueHCYZk0eaY=";
  };

  # Minimal derivation to install the handlers and .desktop file
  cros-container-guest-tools = pkgs.stdenv.mkDerivation {
    pname = "cros-container-guest-tools";
    version = cros-container-guest-tools-src-version;
    src = cros-container-guest-tools-src;

    dontConfigure = true;
    dontBuild = true;
    installPhase = ''
      mkdir -p $out/bin $out/share/applications
      install -Dm755 "$src/cros-garcon/garcon-url-handler"      "$out/bin/garcon-url-handler"
      install -Dm755 "$src/cros-garcon/garcon-terminal-handler" "$out/bin/garcon-terminal-handler"
      install -Dm644 "$src/cros-garcon/garcon_host_browser.desktop" "$out/share/applications/garcon_host_browser.desktop"
    '';
  };

  crosBin = "/opt/google/cros-containers/bin";
in
{
  imports = [
    "${modulesPath}/virtualisation/lxc-container.nix"
  ];

  networking.firewall.enable = false;

  networking.enableIPv6 = false;
  networking.dhcpcd.IPv6rs = false;
  networking.dhcpcd.wait = "background";
  networking.dhcpcd.extraConfig = "noarp";

  environment.variables.NIX_REMOTE = lib.mkForce "";

  systemd.services."console-getty".enable = false;
  systemd.services."getty@".enable = false;

  documentation.nixos.enable = lib.mkForce false;
  documentation.enable = lib.mkForce true;

  environment.systemPackages = with pkgs; [
    cros-container-guest-tools

    wl-clipboard    # wl-copy / wl-paste
    xdg-utils       # xdg-open -> open in ChromeOS
    usbutils        # lsusb
  ];

  environment.etc = {
    # Tremplin looks for gshadow; stub it so startup doesn't fail
    "gshadow".text = "";
    "gshadow".mode = "0640";
    "gshadow".group = "shadow";

    # Sommelier reads /etc/sommelierrc if present; an empty file avoids errors.
    "sommelierrc".text = "\n";
    "sommelierrc".mode = "0644";
  };

  system.activationScripts = {
    # XKB path for Xwayland (bind-mounted from host in Crostini)
    xkb.text = ''ln -sf ${pkgs.xkeyboard_config}/share/X11/ /usr/share/ || true'';

    # Garcon expects sftp-server at this path
    sftp-server.text = ''
      mkdir -p /usr/lib/openssh/
      ln -sf ${pkgs.openssh}/libexec/sftp-server /usr/lib/openssh/sftp-server
    '';
  };

  environment.shellInit = lib.mkAfter (builtins.readFile
    "${cros-container-guest-tools-src}/cros-sommelier/sommelier.sh");

  xdg.mime.defaultApplications = {
    "text/html"              = "garcon_host_browser.desktop";
    "x-scheme-handler/http"  = "garcon_host_browser.desktop";
    "x-scheme-handler/https" = "garcon_host_browser.desktop";
    "x-scheme-handler/about" = "garcon_host_browser.desktop";
    "x-scheme-handler/unknown" = "garcon_host_browser.desktop";
  };

  systemd.user.services.garcon = {
    description = "Chromium OS Garcon Bridge";
    wantedBy = [ "default.target" ];
    after = [ "sommelier@0.service" "sommelier@1.service" ];
    wants = [ "sommelier@0.service" ];

    serviceConfig = {
      Type = "simple";
      ExecStart = "${crosBin}/garcon --server";
      ExecStopPost = "${crosBin}/guest_service_failure_notifier cros-garcon";
      Restart = "always";
      RestartSec = 1;
      Environment = [
        "BROWSER=${lib.getExe' cros-container-guest-tools "garcon-url-handler"}"
        "NCURSES_NO_UTF8_ACS=1"
        "QT_AUTO_SCREEN_SCALE_FACTOR=1"
        "QT_QPA_PLATFORMTHEME=gtk2"
        "XCURSOR_THEME=Adwaita"
        "XDG_CONFIG_HOME=%h/.config"
        "XDG_CURRENT_DESKTOP=X-Generic"
        "XDG_SESSION_TYPE=wayland"
        # Provide user profile/share paths; %h expands at runtime
        "XDG_DATA_DIRS=%h/.nix-profile/share:%h/.local/share:%h/.local/share/flatpak/exports/share:/var/lib/flatpak/exports/share:/usr/local/share:/usr/share"
        "PATH=%h/.nix-profile/bin:/usr/local/sbin:/usr/local/bin:/usr/local/games:/usr/sbin:/usr/bin:/usr/games:/sbin:/bin"
      ];
    };
  };

  systemd.user.services."sommelier@" = {
    description = "Parent sommelier listening on socket wayland-%i";
    wantedBy = [ "default.target" ];
    path = with pkgs; [
      systemd  # systemctl
      bash     # sh
    ];
    serviceConfig = {
      Type = "notify";
      Restart = "always";
      RestartSec = 1;
      ExecStart = ''
        ${crosBin}/sommelier \
          --parent \
          --sd-notify="READY=1" \
          --socket=wayland-%i \
          --stable-scaling \
          --enable-linux-dmabuf \
          sh -c \
            "systemctl --user set-environment ''${WAYLAND_DISPLAY_VAR}=$''${WAYLAND_DISPLAY}; \
             systemctl --user import-environment SOMMELIER_VERSION"
      '';
      ExecStopPost = "${crosBin}/guest_service_failure_notifier sommelier";
      Environment = [
        "WAYLAND_DISPLAY_VAR=WAYLAND_DISPLAY"
        "SOMMELIER_SCALE=1.2"
      ];
    };
  };

  # XWayland (X) sommelier instances
  systemd.user.services."sommelier-x@" = {
    description = "Sommelier X11 parent listening on socket wayland-%i";
    wantedBy = [ "default.target" ];
    path = with pkgs; [
      systemd
      bash
      xorg.xauth
      vim  # provides 'xxd' binary (replace 'tinyxxd' which doesn't exist in nixpkgs)
    ];
    serviceConfig = {
      Type = "notify";
      Restart = "always";
      RestartSec = 1;
      ExecStart = ''
        ${crosBin}/sommelier \
          -X \
          --x-display=%i \
          --sd-notify="READY=1" \
          --no-exit-with-child \
          --x-auth="''${HOME}/.Xauthority" \
          --stable-scaling \
          --enable-xshape \
          --enable-linux-dmabuf \
          sh -c \
            "systemctl --user set-environment ''${DISPLAY_VAR}=$''${DISPLAY}; \
             systemctl --user set-environment ''${XCURSOR_SIZE_VAR}=$''${XCURSOR_SIZE}; \
             systemctl --user import-environment SOMMELIER_VERSION; \
             touch ''${HOME}/.Xauthority; \
             xauth -f ''${HOME}/.Xauthority add :%i . $(xxd -l 16 -p /dev/urandom); \
             . /etc/sommelierrc"
      '';
      ExecStopPost = "${crosBin}/guest_service_failure_notifier sommelier-x";
      Environment = [
        "DISPLAY_VAR=DISPLAY"
        "XCURSOR_SIZE_VAR=XCURSOR_SIZE"
        "SOMMELIER_SCALE=1.2"
      ];
    };
  };

  # Start common sockets by default (two Wayland and two X11 displays)
  systemd.user.targets.default.wants = [
    "sommelier@0.service"
    "sommelier@1.service"
    "sommelier-x@0.service"
    "sommelier-x@1.service"
  ];

  services.dbus.enable = true;
}
