#!/usr/bin/env python3
# Copyright (c) 2026 Digitzone
# SPDX-License-Identifier: MIT
"""The Grass workspace's tool and view-strip icons: 24x24 duotone SVGs (a 1.6 px line and a 24 % fill) drawn in the placeholder
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
    'grass_density': '<g fill="#FF00FF" fill-opacity="1" stroke="none"><circle cx="4" cy="7" r="1.5"/><circle cx="4" cy="17" r="1.5"/><circle cx="10" cy="5" r="1.5"/><circle cx="10" cy="12" r="1.5"/><circle cx="10" cy="19" r="1.5"/><circle cx="15.5" cy="4" r="1.5"/><circle cx="15.5" cy="9.3" r="1.5"/><circle cx="15.5" cy="14.6" r="1.5"/><circle cx="15.5" cy="20" r="1.5"/><circle cx="20.5" cy="6.6" r="1.5"/><circle cx="20.5" cy="12" r="1.5"/><circle cx="20.5" cy="17.4" r="1.5"/></g>',
    'grass_height': '<path d="M6 21 C6 14.6 5.4 10.6 3.2 7.4 C6.6 9.4 8.2 13 8.6 17"/><path d="M17 4 V20 M14 7 L17 4 L20 7 M14 17 L17 20 L20 17" fill="none"/>',
    'grass_smooth': '<path d="M2.5 21 H21.5" fill="none"/><path d="M4.6 21 C4.6 17.8 5 15.9 6 14.3 C6.2 16.4 6.4 18.6 6.6 21 Z"/><path d="M10.6 21 C10.6 15.4 11.2 10.6 12.8 7.2 C12.8 11.6 13 16 13.2 21 Z"/><path d="M17 21 C17 17.4 17.5 15 18.8 12.8 C18.8 15.6 19 18.2 19.2 21 Z"/><path d="M2.5 10.5 H21.5" fill="none" stroke-dasharray="2 2.2"/>',
    'grass_pick': '<path d="M15.4 4.4 A3 3 0 0 1 19.6 8.6 L17.9 10.3 L13.7 6.1 Z"/><path d="M12.6 5.4 L18.6 11.4" fill="none"/><path d="M14.4 8.2 L15.8 9.6 L7.4 18 L4.6 19.4 L6 16.6 Z"/>',
    'grass_remove': '<path d="M8 21 C8 16 7.4 12.6 5.6 10 C8.4 11.6 9.8 14.6 10.2 18"/><path d="M13 21 C13 15.6 13.8 11.2 16 7.8 C14.8 12 15 16.2 15.4 21 Z"/><circle cx="12" cy="12" r="9" fill="none"/><path d="M5.6 18.4 L18.4 5.6" fill="none"/>',
    'grass_force': '<path d="M2.5 16.5 H21.5 V21 H2.5 Z"/><path d="M11.4 16.5 L12.6 18.3 L11.3 19.6 L12.2 21" fill="none"/><path d="M11.6 16.5 C11.6 11.8 12.5 8.4 14.8 5.4 C13.9 9.4 13.7 12.8 13.8 16.5 Z"/><path d="M11 16.5 C10.8 13.2 9.9 11 8.2 9.4 C10.6 10.2 11.9 12.4 12.1 15" fill="none"/>',
    'grass_replace': '<path d="M2.5 21 H10 M14 21 H21.5" fill="none"/><path d="M4 21 C4 18 3.6 16.4 2.8 15.2 C4.4 16 5.2 17.6 5.4 19.4" fill="none"/><path d="M6.6 21 C6.6 18 7.2 16 8.6 14.6 C8 16.8 8 18.8 8.3 21 Z" fill-opacity="0"/><path d="M15.6 21 C15.6 18 15.2 16.4 14.4 15.2 C16 16 16.8 17.6 17 19.4" fill="none"/><path d="M18.2 21 C18.2 18 18.8 16 20.2 14.6 C19.6 16.8 19.6 18.8 19.9 21 Z"/><path d="M5.5 10 C8 5.5 16 5.5 18.5 10" fill="none"/><path d="M15.6 9.6 L18.5 10 L19 7" fill="none"/>',
    'grass_reset': '<rect x="3" y="7" width="14" height="14" rx="2"/><path d="M8 18.5 C8 16.4 7.6 15.1 6.8 14.1 M10.4 18.5 C10.4 15.6 11 13.6 12.6 12" fill="none"/><path d="M14.5 5.2 A4.5 4.5 0 1 1 18.8 11.4" fill="none"/><path d="M14.3 2.4 L14.4 5.4 L17.3 5.1" fill="none"/>',
    'view_eye': '<path d="M2.5 21 H14" fill="none"/><path d="M4.6 21 C4.6 17.6 4.1 15.6 3 14.2 C5 15.2 6 17.2 6.2 19.4" fill="none"/><path d="M8.2 21 C8.2 16.8 9 14 11 11.8 C10.2 14.8 10.2 17.8 10.5 21 Z"/><path d="M12 7 C14.2 3.4 19.8 3.4 22 7 C19.8 10.6 14.2 10.6 12 7 Z" fill="none"/><circle cx="17" cy="7" r="1.6" fill-opacity="1"/>',
    'view_every_ground': '<rect x="3" y="3" width="8" height="8" rx="1.5"/><rect x="13" y="3" width="8" height="8" rx="1.5"/><rect x="3" y="13" width="8" height="8" rx="1.5"/><rect x="13" y="13" width="8" height="8" rx="1.5"/><path d="M5.8 9.6 C5.8 8 5.4 7 4.8 6.2 M7.6 9.6 C7.6 7.4 8.1 5.9 9.2 4.8 M15.8 9.6 C15.8 8 15.4 7 14.8 6.2 M17.6 9.6 C17.6 7.4 18.1 5.9 19.2 4.8 M5.8 19.6 C5.8 18 5.4 17 4.8 16.2 M7.6 19.6 C7.6 17.4 8.1 15.9 9.2 14.8 M15.8 19.6 C15.8 18 15.4 17 14.8 16.2 M17.6 19.6 C17.6 17.4 18.1 15.9 19.2 14.8" fill="none" stroke-width="1.3"/>',
}


def write(out: pathlib.Path, icons: dict) -> None:
    out.mkdir(parents=True, exist_ok=True)
    (out / ".gdignore").write_text("")       # loaded as text by ux_icons.gd, never imported
    for name, body in icons.items():
        (out / f"{name}.svg").write_text(HEAD + body + "</svg>\n")
    print(len(icons), "icons ->", out)


if __name__ == "__main__":
    write(OUT, GRASS)
