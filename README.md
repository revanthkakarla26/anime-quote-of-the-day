# Anime Quote of the Day

An Omarchy shell bar widget that shows one anime quote per day with a portrait
of its character. The daily quote is selected from a date-seeded shuffle, so
it remains stable all day and quotes are used before the cycle repeats.

## Features

- Hover over the bar widget to read today's quote.
- Left click to open the quote popup; choose **Another** for a random quote or
  **Today's** to return to the daily quote.
- Right click to open a random quote.
- Optionally announce the daily quote as a notification.
- Includes an application launcher entry for a random quote.
- Quotes are stored in `quotes.json`; portraits are cached in `images/`.

## Install

On Omarchy, install from this GitHub repository with:

```sh
omarchy plugin add https://github.com/revanthkakarla26/anime-quote-of-the-day.git --enable
```

To enable or disable an already installed copy:

```sh
omarchy plugin enable reva.animequote --section center
omarchy plugin disable reva.animequote
```

## macOS installation guide

The macOS version is a separate SwiftBar menu bar plugin at
`macos/swiftbar/animequote.10m.py`. It shows the date-seeded quote and
character, can choose a random quote or return to today's quote, can send a
notification on request, and links to the character portrait. It reuses
`quotes.json` and `images/` and works offline.

### Requirements

- macOS 12 or newer.
- [SwiftBar](https://swiftbar.app/) and Python 3.
- GitHub CLI (`gh`) access to clone this private repository. If you do not
  have Homebrew, install it from [brew.sh](https://brew.sh/).

### Install

Install the apps and sign in to GitHub if needed:

```sh
brew install --cask swiftbar
brew install python gh
gh auth login
```

Clone the repo and add its plugin to a dedicated SwiftBar folder:

```sh
mkdir -p ~/Projects ~/swiftbar-plugins
gh repo clone revanthkakarla26/anime-quote-of-the-day ~/Projects/anime-quote-of-the-day
chmod +x ~/Projects/anime-quote-of-the-day/macos/swiftbar/animequote.10m.py
ln -s ~/Projects/anime-quote-of-the-day/macos/swiftbar/animequote.10m.py ~/swiftbar-plugins/
```

On first launch, set `~/swiftbar-plugins` as SwiftBar's plugin folder. If
SwiftBar is already running, choose that folder in its settings, then refresh
the plugins. The menu refreshes every 10 minutes and when opened.

### Use and update

Click the quote in the menu bar to see today's quote. Choose **Random quote**
to display another, **Today's quote** to return to the daily selection, or
**Notify today's quote** to send a macOS notification. **View character
portrait** opens the local image. To update, pull the repo; the symlink keeps
SwiftBar connected to the updated script and data.

### Uninstall

Remove the SwiftBar link and, if desired, the cloned repo:

```sh
rm ~/swiftbar-plugins/animequote.10m.py
rm -rf ~/Projects/anime-quote-of-the-day
```

The Omarchy plugin remains documented and installed separately above.

## Configure

Set options on the plugin's entry in `~/.config/omarchy/shell.json`, or use
`omarchy bar set`:

```sh
omarchy bar set reva.animequote showName true
```

| Option | Default | Description |
| --- | --- | --- |
| `showName` | `false` | Show the character name beside the portrait. |
| `notify` | `true` | Announce the daily quote once per day. |
| `maxLabelWidth` | `140` | Maximum character name width in pixels. |

## Commands

```sh
omarchy-shell reva.animequote toggle  # open or close the popup
omarchy-shell reva.animequote random  # show a random quote
omarchy-shell reva.animequote today   # return to today's quote
omarchy-shell reva.animequote notify  # send today's notification again
```

The last announced date is stored at
`~/.local/state/reva.animequote/announced`. If an edit does not appear after
hot reload, restart the shell with `omarchy restart shell`.

## Add quotes and portraits

Add a character under `characters` in `quotes.json` with a unique slug, name,
anime, and optional AniList search term. Add one or more quote objects under
`quotes`, using the character slug in `by`:

```json
{
  "by": "character-slug",
  "text": "A short quote goes here."
}
```

Fetch missing portraits with:

```sh
python3 -I fetch-images.py
```

The script only fetches characters without a picture, checks that AniList
matches the expected anime, and writes the AniList ID and image path into
`quotes.json`. If it selects the wrong character, set that character's
`"anilist"` field to the correct ID and run `python3 -I fetch-images.py
--force`.

Portraits are sourced from AniList and remain subject to the rights of their
respective owners. Check those rights before redistributing the `images/`
folder or publishing a public copy of this repository.

## Repository contents

- `AnimeQuote.qml` — widget, popup, daily draw, and notification behavior.
- `quotes.json` — character metadata and quote text.
- `images/` — cached character portraits.
- `fetch-images.py` — helper for retrieving missing portraits from AniList.
- `manifest.json` — Omarchy plugin metadata and settings schema.
- `macos/swiftbar/` — SwiftBar menu bar version for macOS.

## Development

Clone this repository and edit the plugin files. For local testing, copy the
updated files into `~/.config/omarchy/plugins/reva.animequote/`; Omarchy
hot-reloads user plugin code. Restart the shell if a change does not appear:

```sh
omarchy restart shell
```

Validate the manifest with Omarchy's plugin validator if available:

```sh
omarchy plugin validate ~/.config/omarchy/plugins/reva.animequote
```
