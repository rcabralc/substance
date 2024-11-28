# Substance, a color scheme generator inspired by [Material Design](https://m3.material.io/)

All color schemes in your box matching one another, finally! Use the same color scheme for your desktop environment, your terminal, your editor, and possibly more.

This is a Ruby project, which actually has two parts:

- a color scheme generator, and
- some color schemes, one of which is named “Substance”

By having a sensible set of colors for your terminal, a number of TUI apps can be readily supported (like ranger, btop, lazygit, etc), while matching the whole desktop color scheme.

Also, light and dark variations of the available color schemes are supported.

## Usage

TODO

## Colors description

TODO

## Desktop Environments

Only Plasma is supported for now.

## Terminals

Most TUI applications rely on the 16-colors (indexed colors from 0 to 15) because most terminals support it. This project sets these 16 colors, plus “faint” colors (which some terminals support).

In practice, the “faint” colors are seldom used. I only have seen them by echoing escape ANSI codes by hand, never seen them in a TUI application.

Only Konsole, Foot, Alacritty, Ghostty and Linux VT are supported for now.

## Editors

Only Kakoune is really supported for now.

Sublime have a color scheme template but it's only used to support [bat](https://github.com/sharkdp/bat).

## Other apps

- [bat](https://github.com/sharkdp/bat)
	This is to ensure its colors match more closely your editor. Support for it is currently achieved by the Sublime template.

## FAQ

**Q: Why terminal foreground is different from editor/desktop foreground color?**

**A**: Terminal dimmed colors are mapped to the “mild” colors, which are computed to have the same contrast level between the normal foreground color and normal background color (called respectivelly "On Surface" and “Surface” – names inspired by Material Design). But, in order to have an increased contrast between the terminal foreground color and terminal colors used as background, a special On- color is used, called “On Surface Term”, which is lighter (darker) in dark (light) schemes than the normal foreground color, and assigned to the index 7. The color assigned to the index 15 is the “On Surface Intense” color, providing even more contrast.
