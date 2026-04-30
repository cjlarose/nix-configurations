---
name: nix-configurations:transcode-media
description: Add downloaded media to the Jellyfin library on the media microvm — probe, symlink, or transcode as needed
---

# transcode-media

Add downloaded media from the transmission completed directory to the Jellyfin library on the media microvm. Probe the files first to determine if transcoding is needed or if they can be symlinked directly.

This runs on **ns1010301** (the microvm host). ffmpeg is not installed — use `nix-shell -p ffmpeg` to get it.

## Paths

All paths are on the media microvm's virtiofs-mounted storage, accessible from the host at `/var/lib/microvms/media/media/`:

- **Transmission completed**: `/var/lib/microvms/media/media/transmission-openvpn/data/completed/`
- **Jellyfin Movies**: `/var/lib/microvms/media/media/jellyfin-media/Movies/`
- **Jellyfin Shows**: `/var/lib/microvms/media/media/jellyfin-media/Shows/`

The Jellyfin directories are owned by `jellyfin:jellyfin` (uid 998, gid 998) with mode 700. All commands that write to them must use `sudo`.

## Step 1: Probe the downloaded files

Before doing anything, examine the source file(s) with ffprobe:

```sh
nix-shell -p ffmpeg --run 'ffprobe "<source-file>" 2>&1 | grep -E "Stream|Duration|bitrate"'
```

Report the following to the user:
- **Video codec** (H.264, H.265/HEVC, AVC, etc.) and bitrate
- **Audio codec** (AAC, EAC3/DDP, DTS-HD MA, TrueHD, etc.)
- **Subtitles**: whether they exist, how many tracks, and their format (SRT/subrip = text-based, PGS/hdmv_pgs_subtitle = bitmap-based)
- **Direct play assessment**: whether the file is likely to direct play without transcoding

### Direct play compatibility (macOS Jellyfin Media Player)

The macOS desktop client (Jellyfin Media Player) has broad codec support:
- **Video**: H.264, H.265/HEVC (8-bit and 10-bit), VP9, AV1 all direct play.
- **Audio**: All formats direct play, including AAC, EAC3, AC3, DTS, DTS-HD MA, TrueHD, FLAC, and Opus.
- **Containers**: MKV, MP4, WebM, TS all supported.
- **Subtitles**: SRT, ASS/SSA, PGS, VobSub all render natively without server-side transcoding.
- **Bitrate**: Under ~15 Mbps for reliable streaming over the network.

Transcoding is mainly needed for high-bitrate BluRay remuxes (30+ Mbps) that exceed the available network bandwidth. If bitrate is acceptable, prefer symlinking over transcoding.

**Web browser clients** are more limited: no MKV containers in Firefox (will remux), no DTS audio, limited H.265 support. If users will stream from a browser, transcoding audio to AAC and using MP4 containers may be needed.

## Step 2a: Symlink (if direct-playable)

If the files are already in a good format, symlink them into the Jellyfin library instead of transcoding.

**Important**: Symlink targets must use the **VM-internal path** (`/persistence/media/...`), not the host path (`/var/lib/microvms/media/media/...`). Jellyfin runs inside the VM where the virtiofs mount is at `/persistence/media/`. The commands below run on the host but create symlinks with VM-internal target paths.

### Movies

```sh
sudo ln -sf "/persistence/media/transmission-openvpn/data/completed/<source-file>" \
  "/var/lib/microvms/media/media/jellyfin-media/Movies/<Title> (<Year>).mkv"
sudo chown -h 998:998 "/var/lib/microvms/media/media/jellyfin-media/Movies/<Title> (<Year>).mkv"
```

### TV Shows

Create the directory structure first:

```sh
sudo mkdir -p "/var/lib/microvms/media/media/jellyfin-media/Shows/<Show Name> (<Year>)/Season <N>"
sudo chown -R 998:998 "/var/lib/microvms/media/media/jellyfin-media/Shows/<Show Name> (<Year>)"
```

Then symlink each episode:

```sh
sudo ln -sf "/persistence/media/transmission-openvpn/data/completed/<dir>/<source-file>" \
  "/var/lib/microvms/media/media/jellyfin-media/Shows/<Show Name> (<Year>)/Season <N>/<Show Name> S<NN>E<NN>.mkv"
```

## Step 2b: Transcode (if not direct-playable)

If the video or audio codecs need transcoding:

```sh
nix-shell -p ffmpeg --run 'sudo ffmpeg \
  -i "<source-file>" \
  -c:v libx264 -crf 23 -preset medium \
  -c:a aac -b:a 384k \
  -c:s copy \
  "/var/lib/microvms/media/media/jellyfin-media/Movies/<Title> (<Year>).mkv"'
```

### Key settings

- **`-crf 23`**: Good balance of quality and file size for streaming (~6-8 Mbps). Lower = higher quality/larger file. Range 18-28 is typical.
- **`-preset medium`**: Encoding speed vs compression tradeoff. Use `slow` for better compression if time permits.
- **`-c:a aac -b:a 384k`**: Transcode audio to AAC at 384 kbps. Source files often use DTS-HD MA which most streaming clients can't direct-play.
- **`-c:s copy`**: Copy subtitles as-is.

### Partial transcode (video passthrough)

If only the audio needs transcoding (e.g., H.264 video with DTS-HD MA audio):

```sh
-c:v copy -c:a aac -b:a 384k -c:s copy
```

### Adding subtitles to an existing transcode

If a file was transcoded without subtitles, remux them from the original without re-encoding:

```sh
nix-shell -p ffmpeg --run 'sudo ffmpeg \
  -i "transcoded.mkv" -i "original.mkv" \
  -map 0:v -map 0:a -map 1:s:0 -map 1:s:1 \
  -c copy \
  "output.mkv"'
```

This takes seconds, not minutes.

## After transcoding

Fix ownership so Jellyfin can read the file:

```sh
sudo chown 998:998 "/var/lib/microvms/media/media/jellyfin-media/Movies/<Title> (<Year>).mkv"
```

The original file in the transmission completed directory should be **kept** so that seeding continues to work.

## Monitoring progress

ffmpeg prints progress to stderr. Run the transcode as a background task and monitor it. Transcoding a full movie typically takes 10-30 minutes depending on length and resolution.
