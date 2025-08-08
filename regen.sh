#!/bin/bash

set -e

usage () {
	echo "Usage:"
	echo "  regen [--alacritty]"
	echo "        [--bat]"
	echo "        [--foot]"
	echo "        [--ghostty]"
	echo "        [--kakoune]"
	echo "        [--kconfig-monitor]"
	echo "        [--konsole]"
	echo "        [--plasma]"
	echo "        [--vt]"
	echo "        [--scheme <Scheme> ...]"
}

fail () {
	>&2 echo "$1"
	>&2 usage
	exit 1
}

regen_alacritty () {
	erb -r ./"$1.rb" "name=$2" variant=light ./alacritty.toml.erb > ~/.config/alacritty/"$1-light.toml"
	erb -r ./"$1.rb" "name=$2" variant=dark ./alacritty.toml.erb > ~/.config/alacritty/"$1-dark.toml"
}

regen_bat () {
	erb -r ./"$1.rb" "name=$2" variant=light ./sublime.tmTheme.erb > ~/.config/bat/themes/"$1-light.tmTheme"
	erb -r ./"$1.rb" "name=$2" variant=dark ./sublime.tmTheme.erb > ~/.config/bat/themes/"$1-dark.tmTheme"
	bat cache --build > /dev/null || true
}

regen_foot () {
	erb -r ./"$1.rb" "name=$2" variant=light ./foot.ini.erb > ~/.config/foot/"$1-light.ini"
	erb -r ./"$1.rb" "name=$2" variant=dark ./foot.ini.erb > ~/.config/foot/"$1-dark.ini"
}

regen_ghostty () {
	erb -r ./"$1.rb" "name=$2" variant=light ./ghostty.erb > ~/.config/ghostty/themes/"$1-light"
	erb -r ./"$1.rb" "name=$2" variant=dark ./ghostty.erb > ~/.config/ghostty/themes/"$1-dark"
}

regen_kakoune () {
	erb -r ./"$1.rb" "name=$2" variant=light ./kakoune.kak.erb > ~/.config/kak/colors/"$1-light.kak"
	erb -r ./"$1.rb" "name=$2" variant=dark ./kakoune.kak.erb > ~/.config/kak/colors/"$1-dark.kak"
}

regen_kconfig_monitor () {
	local patterns=()
	for scheme in ${all_schemes[*]}
	do
		for variant in Dark Light; do patterns+=("$scheme$variant"); done
	done
	local pattern=$(IFS='|'; echo "${patterns[*]}")
	cat ./kconfig-monitor.template | sed "s/__COLOR_SCHEMES__/$pattern/" > ~/.local/bin/kconfig-monitor
	chmod u+x ~/.local/bin/kconfig-monitor
}

regen_konsole () {
	erb -r ./"$1.rb" "name=$2" variant=light ./konsole.colorscheme.erb > ~/.local/share/konsole/"$2Light.colorscheme"
	erb -r ./"$1.rb" "name=$2" variant=dark ./konsole.colorscheme.erb > ~/.local/share/konsole/"$2Dark.colorscheme"
}

regen_plasma () {
	erb -r ./"$1.rb" "name=$2" variant=light ./plasma.colors.erb > ~/.local/share/color-schemes/"$2Light.colors"
	erb -r ./"$1.rb" "name=$2" variant=dark ./plasma.colors.erb > ~/.local/share/color-schemes/"$2Dark.colors"
}

regen_vt () {
	erb -r ./"$1.rb" "name=$2" variant=light ./vt.sh.erb > ~/.config/"vt-colors-$1-light.sh"
	erb -r ./"$1.rb" "name=$2" variant=dark ./vt.sh.erb > ~/.config/"vt-colors-$1-dark.sh"
}

all_per_scheme_items=(alacritty
                      bat
                      foot
                      ghostty
                      kakoune
                      konsole
                      plasma
                      vt)
all_items=(kconfig_monitor)

all_schemes=()
for scheme in $(grep -r -o -P '[A-Z].*(?= = Scheme\.new)' . | cut -d: -f2)
do
	all_schemes+=("$scheme")
done

per_scheme_includes=()
includes=()
only_schemes=()
while [ "$#" -gt 0 ]; do
	case $1 in
		--alacritty)
			per_scheme_includes+=(alacritty)
			;;
		--bat)
			per_scheme_includes+=(bat)
			;;
		--foot)
			per_scheme_includes+=(foot)
			;;
		--ghostty)
			per_scheme_includes+=(ghostty)
			;;
		--kakoune)
			per_scheme_includes+=(kakoune)
			;;
		--kconfig-monitor)
			includes+=(kconfig_monitor)
			;;
		--konsole)
			per_scheme_includes+=(konsole)
			;;
		--plasma)
			per_scheme_includes+=(plasma)
			;;
		--vt)
			per_scheme_includes+=(vt)
			;;
		--scheme)
			shift
			[[ ! " ${all_schemes[*]} " =~ " $1 " ]] && fail "unknown scheme: $1, must be one of ${all_schemes[*]}"
			only_schemes+=("$1")
			;;
		*)
			fail "unknown option: $1"
			;;
	esac
	shift
done

if [ ${#per_scheme_includes[@]} -gt 0 ] || [ ${#includes[@]} -gt 0 ]; then
	per_scheme_items=(${per_scheme_includes[@]})
	items=(${includes[@]})
else
	per_scheme_items=(${all_per_scheme_items[@]})
	[ ${#only_schemes[@]} -gt 0 ] || items=(${all_items[@]})
fi

if [ ${#only_schemes[@]} -gt 0 ]; then
	schemes=(${only_schemes[@]})
else
	schemes=(${all_schemes[@]})
fi

for item in ${per_scheme_items[@]}
do
	echo "regenerating $item..."
	for Name in ${schemes[@]}
	do
		echo -n "  - $Name..."
		name=$(echo "$Name" | tr '[:upper:]' '[:lower:]')
		regen_$item "$name" "$Name"
		echo "ok"
	done
done

for item in ${items[@]}
do
	echo "regenerating $item"
	regen_$item
done
