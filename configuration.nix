{ inputs, lib, config, pkgs, ... }:
{
  networking.hostName = "seagull";

  nix = {
    settings = {
      experimental-features = [ "nix-command" "flakes" ];
      auto-optimise-store = true;
      warn-dirty = false;
    };
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 7d";
    };
  };

  time.timeZone = "America/New_York";
  i18n.defaultLocale = "en_US.UTF-8";

  nixpkgs.config.allowUnfree = true;

  programs.fish.enable = true;

  users.users.chronos = {
    isNormalUser = true;
    home = "/home/chronos";
    shell = pkgs.fish;
    extraGroups = [ "wheel" "docker" "video" "render" ];
    openssh.authorizedKeys.keys = [
    ];
  };

  security.sudo = {
    enable = true;
    wheelNeedsPassword = false;  # convenient in Crostini; tighten if you prefer
  };

  environment.systemPackages = with pkgs; [
    git micro fish tailscale
    docker-compose docker-buildx docker-color-output docker-credential-gcr
	nodejs
    nerd-fonts.jetbrains-mono
    xdg-utils            # xdg-open -> opens URLs/files via ChromeOS integration
    xdg-user-dirs        # creates Desktop/Downloads dirs etc.
    mesa-demos           # glxinfo, glxgears (quick GPU sanity checks)
    vulkan-tools         # vulkaninfo (if using Vulkan wrappers)
    wl-clipboard         # Wayland clipboard helpers (if needed)
    xclip xsel           # X11 clipboard helpers (some apps still expect these)
    alsa-utils           # aplay/arecord for basic audio checks
    file which tree bat fd ripgrep # QoL tools
  ];

  hardware.graphics.enable = true;   # unified switch (NixOS ≥ 24.11)
  hardware.opengl.enable = true;


  # Don’t start a full X server; ChromeOS/sommelier handles display forwarding.
  services.xserver.enable = lib.mkDefault false;

  virtualisation.docker = {
    enable = true;
    enableOnBoot = true;
    autoPrune = {
      enable = true;
      dates = "weekly";
    };
  };

  services.tailscale.enable = true;

  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = false;
    };
  };

  # These make GUI apps inside the container find fonts/icons and user binaries,
  # mirroring what you were doing with a garcon override (we'll also add a user-scope override).
  environment.variables = {
    PATH = "/home/chronos/.nix-profile/bin:/usr/local/sbin:/usr/local/bin:/usr/local/games:/usr/sbin:/usr/bin:/usr/games:/sbin:/bin";
    XDG_DATA_DIRS = "/home/chronos/.nix-profile/share:/home/chronos/.local/share:/home/chronos/.local/share/flatpak/exports/share:/var/lib/flatpak/exports/share:/usr/local/share:/usr/share";
	DISPLAY=":0";
  };

  system.stateVersion = "25.05";
}
