# nix-configurations

## Disabling the Private Nix Cache

If `nixcache.toothyshouse.com` is unavailable, add:

```sh
--option substituters "https://cache.nixos.org"
```
