# PakesY — private BedWars video studio

A local-first video site built with FastAPI, SQLite and FFmpeg. Upload BedWars videos, optionally auto-edit them, leave comments and display a ranked video feed. The primary creator account is **`pa9783531@gmail.com`**. Interface languages: Persian, Urdu, English, Arabic, Hindi, Turkish, Spanish and Chinese.

## Windows — one-click startup (v4)

1. Extract this ZIP into a **writable folder** such as your Desktop or Documents. Do not run from inside ZIP preview.
2. Double-click **`start_windows.bat`**. No manual FFmpeg or FFprobe copy is needed.
3. The launcher automatically checks for **both `ffmpeg.exe` and `ffprobe.exe`**. If missing, it tries a verified Essentials ZIP from the Gyan Windows build publisher listed on FFmpeg.org, then the publisher's GitHub release mirror, then WinGet (`Gyan.FFmpeg.Essentials`) as fallback. Direct downloads are verified against the publisher-provided SHA-256 checksum before installation. The files are kept in the project folder when downloaded directly; no administrator permission or machine PATH changes are needed for that method.
4. If Python 3.10+ is absent and `winget` is available, the launcher attempts to install **Python 3.13 for your Windows user**. It then creates `.venv` and automatically installs the project's Python dependencies. If Python installation is blocked or winget isn't present, follow the clear error and install Python from <https://www.python.org/downloads/windows/>.
5. The site opens at **<http://127.0.0.1:8765>**. Keep the launch window open while using it. On later starts, installed tools and Python dependencies are reused.

**Requirements:** 64-bit Windows 10/11 and internet access on the first launch. The verified Essentials ZIP is about 110 MB, so download can fail if the connection, VPN, firewall or antivirus blocks the provider; no script can guarantee success under those restrictions. If anything goes wrong, the detailed error is saved to **`setup_log.txt`**, next to `start_windows.bat`. The installer does not disable security settings or run as administrator.

## Upgrading from v2

Extract the v4 ZIP as a separate new folder. Before switching, copy your existing **`private_data/`** and **`media/`** folders from v2 into this new `PakesY` folder. Do **not** replace the old data with the empty folders bundled in v3. Then run the new `start_windows.bat`.

## Linux and macOS

Install Python 3.10+, `ffmpeg` and `ffprobe`, then run:

```bash
python -m pip install -r requirements.txt
python -m uvicorn app:app --host 127.0.0.1 --port 8765
```

## Accounts and ranking

- On a **new installation**, create the **primary account first** using `pa9783531@gmail.com` and a password of at least 8 characters.
- Once the primary account exists, others can use **Create account** on the login screen to sign up and upload their own videos. Every user has their own login and can delete only their own uploads.
- Only uploads by the primary email are pinned above other videos, automatically receive staged internal engagement after publishing, and can use the creator's 48-hour preview action. Other creators' uploads get none of those automatic advantages.
- No sample posts, likes or comments are generated at initial registration or login. The home screen starts empty until someone uploads.
- The site does not include a virtual-profile directory or profile counters. Highlight posts are created only from the primary creator's own uploaded footage.
- Auto Edit uses actual FFmpeg operations: montage for long clips, color/clarity adjustments, audio preservation and MP4 publishing. It does **not** detect BedWars highlights using an AI model.
- This private project models reactions from programmed internal personas and uses a **non-cash** rupee score. It is not a real audience, video distribution network or payout service. The interface avoids repeated status notices, but this documentation states the distinction.

If your old owner account used a different email, you can run `python set_featured_email.py` while the server is stopped, then restart PakesY. This procedure requires the old account password.

## Limitations and checks

This version runs locally on `127.0.0.1`, not as a public website. Users on other devices cannot connect to it unless you specifically deploy it on a server. **Email addresses are not verified**, there is no password-reset email service, and security would need additional work before internet exposure. It does not scrape or repost strangers' videos.

Test on a computer with FFmpeg and FFprobe available:

```bash
python smoke_test.py
python smoke_multiuser.py
```

## v4 HTML/CSS repair and GitHub Pages compatibility

The stylesheet, JavaScript and icon paths are now relative (`./assets/...`), fixing the unstyled HTML that appeared when viewing `index.html` from a subdirectory or a GitHub Pages project URL. A styled preview remains visible when the Python API is unavailable. **GitHub Pages hosts only the static preview**; uploading, signing in and Auto Edit require the locally running FastAPI server or separate server deployment.

Keep the `assets` folder next to `index.html` when uploading to GitHub. See `GITHUB-راهنما.md` for Persian instructions.
