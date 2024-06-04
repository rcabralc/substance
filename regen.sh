#!/usr/bin/sh

for Name in Redefined Substance
do
	name=$(echo "$Name" | tr '[:upper:]' '[:lower:]')
	for Variant in Dark Light
	do
		variant=$(echo "$Variant" | tr '[:upper:]' '[:lower:]')
		erb -r ./${name}.rb name=${Name} variant=${variant} ${name}/alacritty.toml.erb > ~/.config/alacritty/${name}-${variant}.toml
		erb -r ./${name}.rb name=${Name} variant=${variant} ${name}/foot.ini.erb > ~/.config/foot/${name}-${variant}.ini
		erb -r ./${name}.rb name=${Name} variant=${variant} ${name}/kakoune.kak.erb > ~/.config/kak/colors/${name}-${variant}.kak
		erb -r ./${name}.rb name=${Name} variant=${variant} ${name}/konsole.colorscheme.erb > ~/.local/share/konsole/${Name}${Variant}.colorscheme
		erb -r ./${name}.rb name=${Name} variant=${variant} ${name}/plasma.colors.erb > ~/.local/share/color-schemes/${Name}${Variant}.colors
		mkdir -p ~/.config/bat/themes
		erb -r ./${name}.rb name=${Name} variant=${variant} ${name}/sublime.tmTheme.erb > ~/.config/bat/themes/${name}-${variant}.tmTheme
	done
done
