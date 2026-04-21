# Q2 result

**Outcome**: YES
**Browser**: Chromium (Playwright MCP, headful)
**Wallet version**: v2.5.4-beta (build v2.5.4-1773990911043)
**Derived address matched expected**: yes
**Listener tool**: ncat

## Captured evidence

- Wallet displayed: "Done! redirecting you and sharing some exported data back to the site: http://localhost:8080/?r=1-H4sIAAAAAAAAAx1QW0pFMQzcy..."
- Browser navigated to `http://localhost:8080/?r=<payload>` after clicking "Return with data"
- First 80 chars of `r=` payload: `1-H4sIAAAAAAAAAx1QW0pFMQzcy_n2I68mrasQd5CkqYiich-gyN27vTIQEibMTPJ71PfX5-ly`
- Full payload (from wallet snapshot): `1-H4sIAAAAAAAAAx1QW0pFMQzcy_n2I68mrasQd5CkqYiich-gyN27vTIQEibMTPJ71PfX5-lyPh5_j6fTZ9Rzna_vl_t4fn358Mv1VMfj0aV1USdAMjVFFRUjbcbGrfMACKFijDDngdDIMRpWDVIpotqERMsqK1LXajmGqkgGGYgIDlormLCrA2_5RrlwbqNluWCNCuQKG2A8Zm4bVNWuaLxr22si7b_LjbXTQoZoDnTuExv1qdCmJOIEGto8crlAV5474xRFKVjhNXXpbAALeAS5p3BnhOqCy8BLucfkRA7Zx4voshU2cSptpidFFxsGcDwcb_Wzn7dtcIPJCEAJWycYE7MA7-Je6K7Kdefdqts-JCJ78s6U03yOYWi7ieHWZ1Hqcbvd_gC8jllfvQEAAA`
- Payload length: 436 bytes
- Payload encoding: gzip + base64url (prefix `1-H4sI`), NOT LZMA-alone

## Important findings beyond Q2

1. **Encoding mismatch**: The Haskell library's `LzmaAlone` encoder produces LZMA-alone format, but the wallet v2 API (`/api/2/run/`) expects **gzip** encoding (prefix `1-`, then gzip base64url). The official `@gamechanger-finance/gc` JS SDK confirms: `DefaultAPIEncodings: {"1": "json-url-lzw", "2": "gzip"}`. LZMA-alone URLs produce `"both arguments must be objects or arrays"` errors in the wallet.

2. **Security warning**: The wallet warns users about non-HTTPS `returnURLPattern` with: "This script will later redirect you to an unsafe, non 'https' URL. The origin URL of this script is unknown". User must click "Continue" to proceed.

3. **Manual redirect**: The wallet does NOT auto-redirect. After signing, it shows a "Return with data" button the user must click. This is a user-facing action, not automatic.

4. **Wallet host**: The JS SDK uses `https://wallet.gamechanger.finance/` for both mainnet and preprod (with `?networkTag=preprod`), not `https://beta-preprod-wallet.gamechanger.finance/`. Beta-preprod still works but shows "Beta Program is over. Migrate now!".

## Notes

- The probe's own LZMA-alone encoding was bypassed for this test. The resolver URL was generated using the official `@gamechanger-finance/gc` npm package.
- GHC 9.12.3 built from source (~25 min) as it's not in the IOG binary cache. Consider pushing to Cachix.
- Console warnings about `inline-macro-maybe-text` are benign: the wallet's ISL parser tries to interpret literal strings as macro expressions, falls back to literal values.
- The `return: {mode: "last"}` triggered a similar benign warning (wallet tried to parse "last" as ISL macro).
