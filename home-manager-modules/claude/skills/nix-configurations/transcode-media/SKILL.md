---
name: nix-configurations:transcode-media
description: Transcode media from the transmission completed directory and place it into the Jellyfin library on the media microvm
---

# transcode-media

Transcode a downloaded file from the transmission completed directory and place the result into the appropriate Jellyfin media library directory on the media microvm.

This runs on **ns1010301** (the microvm host). ffmpeg is not installed — use `nix-shell -p ffmpeg` to get it.

## Paths

All paths are on the media microvm's virtiofs-mounted storage, accessible from the host at `/var/lib/microvms/media/media/`:

- **Transmission completed**: `/var/lib/microvms/media/media/transmission-openvpn/data/completed/`
- **Jellyfin Movies**: `/var/lib/microvms/media/media/jellyfin-media/Movies/`
- **Jellyfin Shows**: `/var/lib/microvms/media/media/jellyfin-media/Shows/`

The Jellyfin directories are owned by `jellyfin:jellyfin` (uid 998, gid 998) with mode 700. All commands that write to them must use `sudo`.

## Transcode command

```sh
nix-shell -p ffmpeg --run 'sudo ffmpeg \
  -i "/var/lib/microvms/media/media/transmission-openvpn/data/completed/<source-file>" \
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

### Video passthrough (no re-encode)

If the source video codec is already H.264 and only the audio or container needs transcoding:

```sh
-c:v copy
```

## Naming conventions

- **Movies**: `<Title> (<Year>).mkv` — e.g., `The Devil Wears Prada (2006).mkv`
- **TV Shows**: Place in `<Show Name> (<Year>)/Season <N>/` with files named `<Show Name> S<NN>E<NN>.mkv`

## After transcoding

Fix ownership so Jellyfin can read the file:

```sh
sudo chown 998:998 "/var/lib/microvms/media/media/jellyfin-media/Movies/<Title> (<Year>).mkv"
```

The original file in the transmission completed directory should be **kept** so that seeding continues to work.

## Monitoring progress

ffmpeg prints progress to stderr. Run the transcode as a background task and monitor it. Transcoding a full movie typically takes 10-30 minutes depending on length and resolution.
