{ config, pkgs, lib, ... }:

{
  home = {
    username      = "chronos";
    homeDirectory = "/home/chronos";
    stateVersion  = "25.05";

    packages = with pkgs; [
      # GPU wrapper (works well in Crostini via virtGL)
      nixgl.auto.nixGLDefault

      # your originals / dev QoL
      git gh
      direnv
      fzf
      tree
      bat
      cachix
      xclip
      micro

      # handy extras
      fd
      ripgrep
      nix-index
      nix-index-update
    ];

    # Add ~/.nix-profile/bin and ~/.local/bin to PATH
    sessionPath = [
      "$HOME/.nix-profile/bin"
      "$HOME/.local/bin"
    ];

    # Keep ChromeOS garcon happy for GUI apps
    # (Avoid shell expansions like :$XDG_DATA_DIRS to keep it stable.)
    sessionVariables = {
      XDG_DATA_DIRS =
        "$HOME/.nix-profile/share:$HOME/.local/share:$HOME/.local/share/flatpak/exports/share:/var/lib/flatpak/exports/share:/usr/local/share:/usr/share";
      EDITOR = "micro";
    };
  };

  	file.".config/fish/config.fish" = {
      source = ./config.fish;
      force = true;
  	};


  # Crostini: ensure garcon picks up Nix env
  xdg.enable = true;
  xdg.configFile."systemd/user/cros-garcon.service.d/override.conf".text = ''
    [Service]
    Environment=PATH=%h/.nix-profile/bin:/usr/local/sbin:/usr/local/bin:/usr/local/games:/usr/sbin:/usr/bin:/usr/games:/sbin:/bin
    Environment=XDG_DATA_DIRS=%h/.nix-profile/share:%h/.local/share:%h/.local/share/flatpak/exports/share:/var/lib/flatpak/exports/share:/usr/local/share:/usr/share
  '';

  # Start/refresh user services on switch
  systemd.user.startServices = "sd-switch";

  programs.home-manager.enable = true;

  # ---- Fish shell (plugins, aliases, fzf integration) ----
  programs.fish = {
    enable = true;
  };

  programs.fzf = {
    enable = true;
    enableFishIntegration = true;
  };

  programs.direnv = {
    enable = true;           # Home Manager wires the fish hook automatically
    nix-direnv.enable = true;
  };

  # Run an ssh-agent
  services.ssh-agent.enable = true;

  # Ensure ~/.ssh and ~/.gnupg exist with secure perms
  home.activation.ensureSshGpgDirs = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    mkdir -p "$HOME/.ssh" "$HOME/.gnupg"
    chmod 700 "$HOME/.ssh" "$HOME/.gnupg"
  '';

  programs.gh = {
    enable = true;
    settings = {
      git_protocol = "https";
      prompt = "enabled";
    };
  };

  programs.git = {
    enable = true;
    userName = "Alex Dalton";
    userEmail = "alexreceivesemails@gmail.com";
    aliases = {
      cleanup = "!git branch --merged | grep -v '\\*\\|master\\|develop' | xargs -n 1 -r git branch -d";
      prettylog = "log --graph --pretty=format:'%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr) %C(bold blue)<%an>%Creset' --abbrev-commit --date=relative";
      root = "rev-parse --show-toplevel";
    };
    extraConfig = {
      branch.autosetuprebase = "always";
      color.ui = true;
      core.askPass = "";            # use terminal prompt
      credential.helper = "store";  # consider libsecret/gnome-keyring for better security
      github.user = "alxdolphin";
      push.default = "tracking";
      init.defaultBranch = "main";
    };
  };

  # Keep nix-index DB fresh weekly (user scope)
  systemd.user.services."nix-index-update" = {
    Unit.Description = "Update nix-index database";
    Service = {
      Type = "oneshot";
      ExecStart = "${pkgs.nix-index-update}/bin/nix-index-update";
    };
    Install.WantedBy = [ "default.target" ];
  };
  systemd.user.timers."nix-index-update" = {
    Unit.Description = "Weekly nix-index database update";
    Timer = {
      OnCalendar = "weekly";
      Persistent = true;
    };
    Install.WantedBy = [ "timers.target" ];
  };
}
