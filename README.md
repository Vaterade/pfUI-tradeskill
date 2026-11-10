# pfUI-tradeskill

An external module for [pfUI](https://github.com/brues-code/pfUI) that adds a task list and a
materials overview beside the game's own profession windows. It needs pfUI, and so ClassicAPI.
Altoholic is optional. Don't run it alongside AdvancedTradeSkillWindow2, which uses the same window.

## Installing

Download `pfUI-tradeskill-vX.Y.Z-classic.zip` from the latest release on the
[Releases page](https://github.com/Vaterade/pfUI-tradeskill/releases) and unzip it into
`Interface/AddOns/`, so there is a `pfUI-tradeskill` folder with `pfUI-tradeskill.toc` directly inside.
Changes in each version are in `CHANGELOG.md`.

## Using it

Press **Queue** at the bottom left of the recipe details.

- **Add** puts the selected recipe on the list, using the amount in the window's quantity box.
- **Start** crafts the first task on the list that has its materials, as many as it can, and **Stop**
  halts it. The game only starts a craft from a click, so press **Start** again for the next task.
  Enchanting needs a target for every cast, so there the button is **Next** and casts one at a time.
- Each task has buttons to change its count (hold Shift for 5), move it and remove it. Click its
  name to select the recipe.

Tasks count down whenever the recipe's craft succeeds, including from the window's own Create
button. Each character has its own list per profession. A task's count is crafts, not items.

## Materials you can make

Adding a recipe also queues the materials it needs that this character can make, when there aren't
enough in its bags, bank, mail and alts. Add Copper Blade without the bars and Smelt Copper goes on
the list too, above the blade, with as many as the bars needed. A chat line says what was added.

- A material from another profession goes on that profession's list: the bars for Blacksmithing
  on the Mining list. It shows with a guessed amount per craft until you next open that profession.
- What other lists will make counts toward this one, so the Blacksmithing materials don't show
  those bars as missing.
- If more than one of your recipes makes the material, nothing is queued for it and chat says so.
- It counts what the whole list needs, so it also tops up what earlier tasks were short of.
- It can be turned off under pfUI's settings, in Thirdparty > Tradeskill.

## Buying from vendors

At a merchant that sells something your tasks need (flux, vials, thread), a **Buy task materials**
button appears under the merchant window. Hover it for the list and the cost; click to buy. It
buys only what's short after your bags, bank, mail and alts, across all your professions, and no
more than your money covers. Chat lists what was bought. A setting buys it as soon as you open the
merchant instead; it's off unless you turn it on.

## Recipe tooltips

Hover a recipe in the profession window to see, before queueing it:

- **Can make**: how many your bags allow now, as the window counts, and how many with everything:
  your bank, mail and alts, plus the materials you can make from them. Materials share one pool,
  so ore isn't counted for two kinds of bar at once.
- **On your task list**: how many are queued, if any.
- **Each reagent**: how many one craft takes and where yours are (bags, bank, mail, alts),
  coloured like the materials table. *can make* marks one you know a recipe for, *vendor* one
  that pfQuest says a vendor sells.

It never changes the window's filters, so it only finds the recipes listed in the window and those
in the recipe list for your professions. It can be turned off in the same settings.

## Missing recipes

Press **Missing**, next to **Queue**, for the recipes of the open profession you haven't learned.
It opens a panel beside the window in place of the task list; **Queue** brings the task list back.

- Each recipe shows its skill level, green when you can learn it at your current rank, the item it
  makes, and how it's learned (trainer, quest...) or where its recipe comes from (vendor, drop...).
- Hover a recipe for its reagents and any level it needs.
- Tick **Learnable now** to narrow the list to what your rank allows.
- With [pfQuest](https://github.com/brues-code/pfQuest) loaded, hovering the recipe item at the
  right of a line names the vendors, mobs and chests it comes from and their zones, and clicking it
  shows them on the world map. [pfQuest-octo-plus](https://github.com/Salahaja/pfQuest-octo-plus)
  gives pfQuest OctoWoW's data. Shift-click links the recipe in chat.

A recipe counts as known when it's in the window, by name or spell, or the game says you know it.
Linked windows (another player's) count only what they list. This replaces the Gromissingcrafts
addon, whose recipe list it uses: LibCrafts-1.0 by Roman Kharitonov, from
[MissingCrafts](https://github.com/refaim/MissingCrafts), with Grom's Survival recipes (MIT, see
`recipes-LICENSE.txt`), converted with `tools/convert-libcrafts.lua`. When Altoholic is loaded, its
copy of the same list is used rather than a second one.

## Materials

The table lists what the tasks still need: **Need**, **Bags**, **Bank**, **Mail** and **Alts**.
Hover a row to see which alt has what.

| Name color | Meaning |
|---|---|
| Green | Enough in your bags |
| Yellow | Enough with your bank |
| Orange | Enough with your mail and alts |
| Red | Not enough anywhere |

Something a task earlier on the list makes comes off what's needed, so smelting bars for a later
task doesn't show those bars as missing.

Your own bags and bank are always live. Mail and alts come from Altoholic, covering your other
characters on the realm, of either faction, since this server lets the factions mail each other, and are as recent as each character's last login. Both can be
turned off under pfUI's settings, in Thirdparty > Tradeskill.

## Bank reminder

Opening your bank tells you if it holds materials your tasks need, in any profession: a message
on screen and a list in chat of how many of each to take. It only counts what your bags are short
of, and says nothing if there's nothing to take. It can be turned off in the same settings.

## Alt reminder

Opening your bank or mailbox also tells you if this character has materials that another
character's task list needs, with how many to send to whom. It covers your other characters on the
realm, of either faction, once they've logged in with this version. This character keeps what its own tasks need, and
what the alt holds comes off, as Altoholic last saw it. Without Altoholic, the alt counts as having
none. It can be turned off in the same settings.

## Testing

`luajit tools/test.lua`

## License

MIT. See `LICENSE`.
