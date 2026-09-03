# Antigravity Usage Widget for Omarchy

This is a custom Omarchy Shell plugin and Antigravity sidecar that pulls your live Antigravity API quotas directly from Google and displays them in a beautiful, compact dropdown menu directly in your top bar.

## Features
- **Live Sync**: Uses an Antigravity background sidecar to pull real quota from the internal Google API every 60 seconds.
- **Auto-Grouping**: Automatically categorizes your usage into Gemini and Claude/GPT tabs.
- **Native Look**: Renders natively within the Omarchy shell using QML, meaning zero electron overhead.
- **High-Res Logo**: Uses the official, true Antigravity app drawer logo.

## Installation

### 1. Install the UI Plugin
Omarchy has built-in support for cloning Git repositories as plugins. Simply run:
```bash
omarchy plugin add https://github.com/your-username/antigravity-usage-widget
```
*(Replace the URL with wherever you pushed this repository)*

### 2. Install the Background Fetcher
The backend fetcher is an Antigravity sidecar script. You just need to create a symlink from the downloaded Omarchy plugin folder into your Antigravity sidecar configuration folder:
```bash
mkdir -p ~/.gemini/config/sidecars
ln -s ~/.config/omarchy/plugins/antigravity-usage-widget/sidecar ~/.gemini/config/sidecars/usage-updater
```

### 3. Restart Services
Finally, tell Omarchy and Antigravity to reload their configurations:
```bash
agy sidecar reload
omarchy restart shell
```

Enjoy!
