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
      fd
      ripgrep
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
		ls="ls -al --color";
		
      }
      (lib.mkIf pkgs.stdenv.isLinux {
        pbcopy  = "xclip -selection clipboard";
        pbpaste = "xclip -selection clipboard -o";
      })
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




    # Prompt override for bobthefish (your __bobthefish_prompt_nix)
    functions.__bobthefish_prompt_nix = {
      description = "Display current nix environment (override theme)";
      body = ''
        [ "$theme_display_nix" = no -o -z "$IN_NIX_SHELL" ]
        and return

        __bobthefish_start_segment $color_nix
        echo -ns N ' '
        set_color normal
      '';
    };

    # Init for all shells (safe, non-interactive too)
    shellInit = ''
      # Ensure $SHELL points at fish from Nix
      set -g SHELL ${pkgs.fish}/bin/fish

      # Tidy PATH-style user paths (Go/bin and ~/bin)
      contains $HOME/code/go/bin $fish_user_paths; or set -Ua fish_user_paths $HOME/code/go/bin
      contains $HOME/bin         $fish_user_paths; or set -Ua fish_user_paths $HOME/bin
    '';

    # Interactive sessions (colors, theme, GPG_TTY, greeting)
    interactiveShellInit = ''
      # GPG TTY for pinentry in terminals
      if isatty
        set -gx GPG_TTY (tty)
      end

      # Greeting: disable
      functions -q fish_greeting; and functions -e fish_greeting
      function fish_greeting; end

      # Bobthefish theme & Dracula palette
      set -g theme_color_scheme dracula

      # Color scheme (from your config)
      set -g fish_color_normal normal
      set -g fish_color_command F8F8F2
      set -g fish_color_quote F1FA8C
      set -g fish_color_redirection 8BE9FD
      set -g fish_color_end 50FA7B
      set -g fish_color_error FF5555
      set -g fish_color_param 5FFFFF
      set -g fish_color_comment 6272A4
      set -g fish_color_match --background=brblue
      set -g fish_color_selection white --bold --background=brblack
      set -g fish_color_search_match bryellow --background=brblack
      set -g fish_color_history_current --bold
      set -g fish_color_operator 00a6b2
      set -g fish_color_escape 00a6b2
      set -g fish_color_cwd green
      set -g fish_color_cwd_root red
      set -g fish_color_valid_path --underline
      set -g fish_color_autosuggestion BD93F9
      set -g fish_color_user brgreen
      set -g fish_color_host normal
      set -g fish_color_cancel -r
      set -g fish_pager_color_completion normal
      set -g fish_pager_color_description B3A06D yellow
      set -g fish_pager_color_prefix white --bold --underline
      set -g fish_pager_color_progress brwhite --background=cyan
    '';
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
