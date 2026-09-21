# Forever Lazy

A small World of Warcraft Classic addon that sells grey junk and repairs your gear when you open a vendor. Written for **Forever** / Classic clients (`Interface 16001`, including Camelot) by Chrome Jesus.

If you came from Retail and keep walking away from the blacksmith with broken armor and a bag full of greys, this is that.

## What it does

When a merchant window opens, Forever Lazy:

1. Repairs equipped gear if the vendor can repair.
2. Sells grey (poor-quality) items from your bags.

Chat messages report repair cost and junk sold. Both features are on by default.

Guild repair is **off** by default. Leave it off on Forever unless you know guild bank repair actually exists on that realm.

## How it works

The addon listens for `MERCHANT_SHOW`. After a short delay (so the merchant UI is ready) it:

- Calls the repair APIs if auto-repair is enabled. If guild repair is enabled and allowed, it tries guild funds first, then falls back to your gold.
- Walks backpack and equipped bags for quality 0 items, skips locked items and items with no vendor value, then uses them at the merchant to sell.
- Runs a second junk pass a moment later so stacks that were still settling can sell.

Settings are stored in `ForeverLazyDB`. Older `ForeverVendorDB` values are copied once if they exist.

Options register in the game Settings panel when that API is available. If it is not, slash commands still toggle everything.

## Install

The folder name **must** be `ForeverLazy` and it must contain `ForeverLazy.toc`.

### From GitHub (zip)

1. Download the [latest source zip](https://github.com/manipulates/ForeverLazy/archive/refs/heads/main.zip).
2. Extract it.
3. Rename the extracted folder from `ForeverLazy-main` to `ForeverLazy` if needed.
4. Copy `ForeverLazy` into:

   `World of Warcraft\_classic_beta_\Interface\AddOns\`

   Use your actual client folder if you play a different Classic install (`_classic_era_`, `_classic_`, etc.).

5. Fully restart the game (or `/reload` after the files are already in AddOns).
6. On the character select screen, click **AddOns** and make sure **Forever Lazy** is enabled.

### With git

```text
cd "World of Warcraft\_classic_beta_\Interface\AddOns"
git clone https://github.com/manipulates/ForeverLazy.git ForeverLazy
```

Restart the client or `/reload`, then enable it on the AddOns list.

## Commands

| Command | What it does |
| --- | --- |
| `/fl` or `/foreverlazy` or `/lv` | Open options |
| `/fl sell` | Toggle auto-sell junk |
| `/fl repair` | Toggle auto-repair |
| `/fl guild` | Toggle guild repair |
| `/fl quiet` | Toggle chat messages |

Same arguments work with `/foreverlazy` and `/lv`.

## Defaults

| Setting | Default |
| --- | --- |
| Auto-sell junk | On |
| Auto-repair | On |
| Use guild repair | Off |
| Chat messages | On |

## Files

- `ForeverLazy.toc` — addon metadata and load list
- `ForeverLazy.lua` — all logic
