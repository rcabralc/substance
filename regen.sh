#!/usr/bin/sh

erb -r ./redefined.rb name=Redefined variant=dark redefined/alacritty.toml.erb > ~/.config/alacritty/redefined-dark.toml
erb -r ./redefined.rb name=Redefined variant=dark redefined/foot.ini.erb > ~/.config/foot/redefined-dark.ini
erb -r ./redefined.rb name=Redefined variant=dark redefined/kakoune.kak.erb > ~/.config/kak/colors/redefined-dark.kak
erb -r ./redefined.rb name=Redefined variant=dark redefined/konsole.colorscheme.erb > ~/.local/share/konsole/RedefinedDark.colorscheme
erb -r ./redefined.rb name=Redefined variant=dark redefined/plasma.colors.erb > ~/.local/share/color-schemes/RedefinedDark.colors

erb -r ./redefined.rb name=Redefined variant=light redefined/alacritty.toml.erb > ~/.config/alacritty/redefined-light.toml
erb -r ./redefined.rb name=Redefined variant=light redefined/foot.ini.erb > ~/.config/foot/redefined-light.ini
erb -r ./redefined.rb name=Redefined variant=light redefined/kakoune.kak.erb > ~/.config/kak/colors/redefined-light.kak
erb -r ./redefined.rb name=Redefined variant=light redefined/konsole.colorscheme.erb > ~/.local/share/konsole/RedefinedLight.colorscheme
erb -r ./redefined.rb name=Redefined variant=light redefined/plasma.colors.erb > ~/.local/share/color-schemes/RedefinedLight.colors

erb -r ./substance.rb name=Substance variant=dark substance/alacritty.toml.erb > ~/.config/alacritty/substance-dark.toml
erb -r ./substance.rb name=Substance variant=dark substance/foot.ini.erb > ~/.config/foot/substance-dark.ini
erb -r ./substance.rb name=Substance variant=dark substance/kakoune.kak.erb > ~/.config/kak/colors/substance-dark.kak
erb -r ./substance.rb name=Substance variant=dark substance/konsole.colorscheme.erb > ~/.local/share/konsole/SubstanceDark.colorscheme
erb -r ./substance.rb name=Substance variant=dark substance/plasma.colors.erb > ~/.local/share/color-schemes/SubstanceDark.colors

erb -r ./substance.rb name=Substance variant=light substance/alacritty.toml.erb > ~/.config/alacritty/substance-light.toml
erb -r ./substance.rb name=Substance variant=light substance/foot.ini.erb > ~/.config/foot/substance-light.ini
erb -r ./substance.rb name=Substance variant=light substance/kakoune.kak.erb > ~/.config/kak/colors/substance-light.kak
erb -r ./substance.rb name=Substance variant=light substance/konsole.colorscheme.erb > ~/.local/share/konsole/SubstanceLight.colorscheme
erb -r ./substance.rb name=Substance variant=light substance/plasma.colors.erb > ~/.local/share/color-schemes/SubstanceLight.colors
