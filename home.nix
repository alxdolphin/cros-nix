{ config, pkgs, lib, ... }:

let
	sources = import /home/chronos/cros-nix/.config/nix/sources.nix;
in {
  home = {
    username      = "chronos";
    homeDirectory = "/home/chronos";
    stateVersion  = "25.05";

    packages = with pkgs; [
      nixgl.auto.nixGLDefault
      git gh
      direnv
      niv
      fzf
      tree
      bat
      cachix
      wl-clipboard xclip xsel
      micro
      docker-compose docker-buildx docker-color-output docker-credential-gcr
      fd
      ripgrep
      tailscale
      code-cursor
      cursor-cli
      nerd-fonts.jetbrains-mono
      xdg-utils xdg-user-dirs
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
	  GDK_BACKEND = "wayland";
	  VK_ICD_FILENAMES = "/usr/local/share/vulkan/icd.d/virtio_icd.i686.json:/usr/share/vulkan/icd.d/virtio_icd.json";
    };
  };


  # Crostini: ensure garcon picks up Nix env
  xdg.enable = true;
  xdg.configFile."systemd/user/cros-garcon.service.d/override.conf".text = ''
    [Service]
    Environment=PATH=%h/.nix-profile/bin:/usr/local/sbin:/usr/local/bin:/usr/local/games:/usr/sbin:/usr/bin:/usr/games:/sbin:/bin
    Environment=XDG_DATA_DIRS=%h/.nix-profile/share:%h/.local/share:%h/.local/share/flatpak/exports/share:/var/lib/flatpak/exports/share:/usr/local/share:/usr/share
  '';

  xdg.desktopEntries.garcon_host_browser = { name = "Host Browser (ChromeOS)"; noDisplay = true; exec = "/usr/bin/garcon-url-handler %u"; terminal = false; type = "Application"; mimeType = [ "text/html" "x-scheme-handler/http" "x-scheme-handler/https" "x-scheme-handler/about" "x-scheme-handler/unknown" "x-scheme-handler/cursor" ]; };
  xdg.mimeApps = { enable = true; defaultApplications = { "text/html" = [ "garcon_host_browser.desktop" ]; "x-scheme-handler/http" = [ "garcon_host_browser.desktop" ]; "x-scheme-handler/https" = [ "garcon_host_browser.desktop" ]; "x-scheme-handler/about" = [ "garcon_host_browser.desktop" ]; "x-scheme-handler/unknown" = [ "garcon_host_browser.desktop" ]; "x-scheme-handler/cursor" = [ "garcon_host_browser.desktop" ]; }; };


  # Start/refresh user services on switch
  systemd.user.startServices = "sd-switch";

  # ---- Fish shell (plugins, aliases, fzf integration) ----
  programs.fish = {
    enable = true;
	interactiveShellInit = lib.strings.concatStrings (lib.strings.intersperse "\n" ([
	  "source ${sources.theme-bobthefish}/functions/fish_prompt.fish"
	  "source ${sources.theme-bobthefish}/functions/fish_right_prompt.fish"
	  "source ${sources.theme-bobthefish}/functions/fish_title.fish"
	  (builtins.readFile ./config.fish)
	  "set -g SHELL ${pkgs.fish}/bin/fish"
	]));
      
    # Aliases (from your config.fish, plus fnix)
    shellAliases = lib.mkMerge [
      {
        ga = "git add";
        gc = "git commit";
        gco = "git checkout";
        gcp = "git cherry-pick";
        gdiff = "git diff";
        gl = "git prettylog";
        gp = "git push";
        gs = "git status";
        gt = "git tag";

        jf = "jj git fetch";
        jn = "jj new";
        js = "jj st";

        fnix = "nix-shell --run fish";
	nano ="micro";
	ls="ls -l --color";		
      }
    ];

    plugins = map (n: {
      name = n;
      src  = sources.${n};
    }) [
      "fish-fzf"
      "fish-foreign-env"
      "theme-bobthefish"
    ];
  };

  programs.fzf = {
    enable = true;
    enableFishIntegration = true;
  };

  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };


  services.ssh-agent.enable = true;

  # Ensure ~/.ssh and ~/.gnupg exist with secure perms
  home.activation.ensureSshGpgDirs = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    mkdir -p "$HOME/.ssh" "$HOME/.gnupg"
    chmod 700 "$HOME/.ssh" "$HOME/.gnupg"
  '';


  programs.nix-index = {
  	enable = true;
  	enableFishIntegration = true;
  };  	

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
}
