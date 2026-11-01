# Samsung SmartThings oven time sync (Windows)

Keeps the clock of a Samsung smart oven in sync with your Windows PC, using the
SmartThings API. Handles summer/winter time automatically. Pure PowerShell:
nothing to install.

## Why

Samsung ovens connected to SmartThings can drift or keep the wrong time after a
daylight-saving switch. The clock can be set through the SmartThings API, but
**Personal Access Tokens created since December 2024 expire after 24 hours**,
so a simple scheduled `curl` with a token no longer works.

This script uses a SmartThings **OAuth-In app** instead: you log in once, and
the script renews its own login on every run (refresh tokens last 30 days and
are replaced on each use).

## Requirements

- Windows 10 or 11 (Windows PowerShell 5.1, built in)
- A Samsung oven added to your SmartThings account
- For creating the app (once): Node.js LTS from https://nodejs.org (see step 1)

## Setup (once, ~10 minutes)

1. **Create the SmartThings app.** In a command prompt:
   ```
   npx @smartthings/cli apps:create
   ```
   - A browser opens: log in with your Samsung account.
   - App type: **OAuth-In App**
   - Display name / description: anything (e.g. "Oven time sync"); skip icon and target URL.
   - Scopes: select **r:devices:\*** and **x:devices:\*** (space bar to select, Enter to confirm)
   - Redirect URI: add **https://httpbin.org/get**
   - Copy the **OAuth Client Id** and **OAuth Client Secret** it prints
     (the secret is shown only once).

   You can uninstall Node.js afterwards; the daily sync doesn't need it.

   > Do **not** use a project in the SmartThings Developer Workspace: that is a
   > different app type that requires an AWS Lambda or web server.

2. Download `oven_sync.ps1` and `Setup.cmd` into a **permanent** folder, e.g.
   `C:\Users\<you>\oven-sync` (the scheduled task runs the script from there).

3. **Double-click `Setup.cmd`** and follow the steps:
   1. Choose **2** and paste the Client Id and Secret.
      (Option 1 tries to create the app automatically with a token from
      account.smartthings.com/tokens, but SmartThings may answer `HTTP 403`.)
   2. Approve access in the browser, then paste the httpbin.org URL you land on.
   3. Pick your oven from the list.

   It sets the oven time once as a test, then creates the scheduled task.
   Windows may ask for **administrator approval** once (click Yes).

## How it works

- Scheduled task **"Oven time sync"** runs daily at **03:05** (just after a
  summer/winter time switch). If the PC is off or asleep then, it runs as soon
  as it's back on, so effectively at the first start-up of each day.
- It runs in the background ("Run whether user is logged on or not", without
  storing your password), so **no window ever appears**.
- Each run: refresh the login → read the PC's local time → send it to the oven
  → log the result in `oven_sync.log`.
- The time sent is the PC's local time, so make sure Windows has the right time zone.

## If it stops working

The login stays valid as long as the task runs at least once every 30 days.
After a longer break, double-click `Setup.cmd` again (it reuses the app, so
only the browser approval and oven choice).

Check `oven_sync.log`, or Task Scheduler → "Oven time sync" → *Last Run Result*
(`0x0` = OK).

## Other commands (PowerShell in the folder)

```
powershell -ExecutionPolicy Bypass -File .\oven_sync.ps1             # sync now
powershell -ExecutionPolicy Bypass -File .\oven_sync.ps1 -Install    # re-create the task
powershell -ExecutionPolicy Bypass -File .\oven_sync.ps1 -Uninstall  # remove the task
```

## Files

- `oven_sync.ps1`: the script
- `Setup.cmd`: double-click to set up
- `oven_config.json`: your app secret + login token, created by setup.
  **Keep private, never commit it** (it's in `.gitignore`).
- `oven_sync.log`: run history

## Notes

- Tested with an oven that accepts the `x.com.samsung.da.currentTime` setting
  via `/configuration/vs/0`. Other models may differ.
- Not affiliated with Samsung or SmartThings.

## Previous version

The old bash + GitHub Actions version (using a Personal Access Token, which
no longer works since tokens expire after 24 hours) is kept on the
[`legacy-github-actions`](../../tree/legacy-github-actions) branch.
