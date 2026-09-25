#!/usr/bin/env python3
# Copyright (c) 2026 Digitzone
# SPDX-License-Identifier: MIT
"""The Grass workspace's tool icons: 24x24 duotone SVGs (a 1.6 px line and a 24 % fill) drawn in the placeholder
colour #FF00FF, which the overlay's src/ux_icons.gd replaces with each tint (Godot's SVG loader has no
currentColor). Edit a drawing here and run it again from the addon's folder:
    python3 tools/icons.py"""
import pathlib

OUT = pathlib.Path(__file__).resolve().parents[1] / "editor" / "icons"
HEAD = ('<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="#FF00FF" '
        'fill-opacity="0.24" stroke="#FF00FF" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round">')
GRASS = {
    'grass_species': '<path d="M6 21 C6 15 5.2 11 3 8 C6.4 9.8 8 13.2 8.4 17"/><path d="M11 21 C11 14 12 8.6 14.6 4.4 C13.2 9.6 13.4 14.8 13.8 21 Z"/><circle cx="18.6" cy="16.4" r="2.6"/>',
    'grass_erase': '<path d="M3.8 15.6 L12.2 7.2 L18.6 13.6 L13 19.2 H7.4 Z"/><path d="M8.2 11.4 L14.6 17.8 M13 19.2 H21" fill="none"/>',
    'grass_density': '<g fill="#FF00FF" fill-opacity="1" stroke="none"><circle cx="5" cy="5" r="1.7"/><circle cx="12" cy="5" r="1.7"/><circle cx="19" cy="5" r="1.7"/><circle cx="5" cy="12" r="1.7"/><circle cx="12" cy="12" r="1.7"/><circle cx="19" cy="12" r="1.7"/><circle cx="5" cy="19" r="1.7"/><circle cx="12" cy="19" r="1.7"/><circle cx="19" cy="19" r="1.7"/></g>',
    'grass_height': '<path d="M6 21 C6 14.6 5.4 10.6 3.2 7.4 C6.6 9.4 8.2 13 8.6 17"/><path d="M17 4 V20 M14 7 L17 4 L20 7 M14 17 L17 20 L20 17" fill="none"/>',
    'grass_smooth': '<path d="M5 21 C5 17 4.5 14 3 12 M9 21 C9 16 9.5 13 11 10" fill="none"/><path d="M13 16 C15.5 13.5 18.5 13.5 21 16" fill="none"/><path d="M13 20 C15.5 17.5 18.5 17.5 21 20" fill="none"/>',
    'grass_pick': '<path d="M15.2 3.4 L20.6 8.8 L17.8 11.6 L12.4 6.2 Z"/><path d="M13.8 7.6 L5.6 15.8 L4.6 19.4 L8.2 18.4 L16.4 10.2" fill="none"/>',
    'grass_remove': '<path d="M8 21 C8 16 7.4 12.6 5.6 10 C8.4 11.6 9.8 14.6 10.2 18"/><path d="M13 21 C13 15.6 13.8 11.2 16 7.8 C14.8 12 15 16.2 15.4 21 Z"/><circle cx="12" cy="12" r="9" fill="none"/><path d="M5.6 18.4 L18.4 5.6" fill="none"/>',
    'grass_force': '<path d="M9 21 C9 15 8.2 11 6 8 C9.4 9.8 11 13.2 11.4 17"/><path d="M13 21 C13 17 13.4 14 14.4 11.4"/><path d="M17.4 2.8 L13.6 10 H17 L14.4 16.4 L20.2 8.2 H16.8 Z"/>',
    'grass_replace': '<path d="M4 8 H17 M14 5 L17 8 L14 11" fill="none"/><path d="M20 16 H7 M10 13 L7 16 L10 19" fill="none"/><circle cx="5" cy="16" r="2"/><circle cx="19" cy="8" r="2"/>',
    'grass_reset': '<path d="M5.2 13 A7 7 0 1 0 8.2 6.6" fill="none"/><path d="M8.6 2.8 L8.2 6.6 L4.4 6.2" fill="none"/><path d="M11 20 C11 16.4 10.6 14 9.4 12.2 C11.4 13.4 12.4 15.2 12.6 17.4"/>',
}


def write(out: pathlib.Path, icons: dict) -> None:
    out.mkdir(parents=True, exist_ok=True)
    (out / ".gdignore").write_text("")       # loaded as text by ux_icons.gd, never imported
    for name, body in icons.items():
        (out / f"{name}.svg").write_text(HEAD + body + "</svg>\n")
    print(len(icons), "icons ->", out)


if __name__ == "__main__":
    write(OUT, GRASS)
