{ pkgs, lib, ... }:

let
  buildOptions = {
    default = {};
    minimalNormal = {
      features = "normal";
      guiSupport = false;
      luaSupport = false;
      pythonSupport = false;
      rubySupport = false;
      netbeansSupport = false;
    };
  };
  postInstallsAppends = {
    default = "";
    minimalNormal = ''
      find $out/share/vim/vim90/doc -type f -delete
      find $out/share/vim/vim90/lang -type f -delete
      find $out/share/vim/vim90/tutor -type f -delete
      find $out/share/vim/vim90/syntax/shared -type f -delete
      find $out/share/vim/vim90/syntax -type f \( -name xs.vim -o -name nginx.vim -o -name pfmain.vim \) -delete
    '';
  };
  pluginSets = with pkgs.vimPlugins; {
    default = {
      start = [ vim-nix vim-sensible lightline-vim ];
      opt = [];
    };
    minimalNormal = {
      start = [ vim-nix vim-sensible lightline-vim ];
      opt = [];
    };
  };
  vimRcConfigs = with pkgs.vimPlugins; {
    default = {};
    minimalNormal = {
      customRC = ''
        " your custom vimrc
        set nocompatible
        set backspace=indent,eol,start
        " Turn on syntax highlighting by default
        syntax on
        set ts=2
        set sw=2
        set expandtab
        " ...
      '';
    };
  };

  makeVim = name: 
  let lookup = which:
    which."${name}" or which.default or null;  
  in ((pkgs.vim_configurable.override (lookup buildOptions)
  ).overrideAttrs (self: {
    postInstall = self.postInstall + (lookup postInstallsAppends);
  })).customize {
    name = "vim";
    vimrcConfig = {
      packages.myplugins = (lookup pluginSets);
    } // (lookup vimRcConfigs);
  };

  
in
 
  builtins.listToAttrs (
    builtins.map (v: lib.nameValuePair v (makeVim v)) [
      "minimalNormal"
      ])
      
        #buildOptions."minimalNormal" or "buildOptions".default or null
