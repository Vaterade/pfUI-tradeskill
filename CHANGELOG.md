# Changelog

Each release gets a section here, newest first. The release workflow copies the section for
the version in `pfUI-tradeskill.toc` into the GitHub release notes, so write it for players.

Versions follow [semantic versioning](https://semver.org/): a fix raises the last number, a
new feature the middle one. While the first number is 0 the addon isn't considered stable yet.

## [0.4.0] - 2026-11-10

### Added
- Hovering a recipe in the profession window shows how many you can make now and with
  everything (bank, mail, alts and the materials you can make), how many are on your task list,
  and for each reagent where yours are, whether you can make it and whether a vendor sells it.
  It can be turned off in the settings.

## [0.3.0] - 2026-11-08

### Added
- Adding a recipe also queues the materials it needs that you can make and don't have enough
  of, counting your bags, bank, mail and alts: Copper Blade brings Smelt Copper with it. A
  material from another profession goes on that profession's list.
- A **Buy task materials** button on merchants that sell what your tasks need, buying only
  what's short. A setting buys it automatically when the merchant opens; it's off by default.

### Changed
- What one profession's list will make counts toward the others, so bars queued on the Mining
  list aren't shown as missing for Blacksmithing.

## [0.2.1] - 2026-11-07

### Changed
- With Altoholic loaded, its copy of the shared code (vendors, drops and the map for missing
  recipes, and the recipe name helpers) is used, as its recipe list already was, so only one
  copy runs.

## [0.2.0] - 2026-11-07

### Added
- **Missing**, next to **Queue**, opens a panel listing the recipes of the open profession you
  haven't learned, with their skill level, how they're learned or where their recipe comes
  from, and their reagents. Tick **Learnable now** to narrow it to what your rank allows. It
  replaces the Gromissingcrafts addon.
- With pfQuest loaded, a missing recipe's item names who sells or drops it and where, and a
  click shows them on the map.
- A red **X** in each panel's corner closes it.
- Other addons can queue crafts for any character on the realm (Altoholic's Recipes page does).

### Changed
- Renamed from pfUI-trades to pfUI-tradeskill. Rename `pfUI-trades.lua` to
  `pfUI-tradeskill.lua` in your `WTF` saved variables to keep your task lists.
- **Queue** and **Missing** take turns beside the window: opening one closes the other.
- The panels line up with the profession window: the same height, title and button rows level
  with the window's, and darker panes behind the lists like the window's own.
- The "Altoholic: N alts" line under the materials is gone; the table has that row instead.

## [0.1.0] - 2026-11-05

The first release.

### Added
- A task list beside the profession windows. **Queue** at the bottom left of the recipe
  details opens it; **Add** puts the selected recipe on it with the window's quantity.
- **Start** crafts the first task that has its materials, one batch per press, and **Stop**
  halts it. In Enchanting the button is **Next** and casts one at a time.
- A materials table showing what the tasks still need against your bags, bank, mail and
  alts (mail and alts from Altoholic, if it's installed).
- A bank reminder listing materials to take out for your tasks.
- An alt reminder at the bank and mailbox listing materials to send to your other characters.

[0.4.0]: https://github.com/Vaterade/pfUI-tradeskill/releases/tag/v0.4.0
[0.3.0]: https://github.com/Vaterade/pfUI-tradeskill/releases/tag/v0.3.0
[0.2.1]: https://github.com/Vaterade/pfUI-tradeskill/releases/tag/v0.2.1
[0.2.0]: https://github.com/Vaterade/pfUI-tradeskill/releases/tag/v0.2.0
[0.1.0]: https://github.com/Vaterade/pfUI-tradeskill/releases/tag/v0.1.0
