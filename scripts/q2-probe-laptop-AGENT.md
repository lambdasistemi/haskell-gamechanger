# Q2 probe — laptop AI agent brief

You are an AI coding agent (Claude Code or equivalent) running on
the user's **laptop** because this probe needs a real browser + a
real GameChanger wallet extension / page that the headless work
machine does not have. Your job: drive the user through running
the probe and report the outcome back in a form the work-machine
agent can act on.

## Context (what you are probing)

Issue #25 on `lambdasistemi/haskell-gamechanger` needs the
library's CLI UX to deliver wallet results to a one-shot
**`http://localhost:<port>` callback**. That only works if the
beta-preprod GameChanger wallet actually follows
`http://localhost` redirects in `returnURLPattern`. Nobody has
confirmed this by experiment. This probe is the experiment.

- Spec: `specs/007-haskell-client-cli/spec.md` (Q2 in Open Questions)
- Probe source: `scripts/q2-probe.hs`
- Cabal stanza: `haskell-gamechanger.cabal` → `executable q2-probe`
- Branch this lives on: `007-haskell-client-cli`

## Preconditions to verify before running

1. Laptop has `nix` installed with flakes enabled.
2. Laptop has a modern browser (Chrome/Firefox/Brave with a
   normal profile — NOT headless).
3. Port 8080 is free on `localhost`.

Run these checks and report if any fail. Do not try to fix
them autonomously — ask the user.

```
nix --version
lsof -i :8080 || echo "port 8080 free"
```

## Steps

### 1. Clone + check out

```
git clone git@github.com:lambdasistemi/haskell-gamechanger.git
cd haskell-gamechanger
git fetch origin
git checkout 007-haskell-client-cli
```

(If SSH isn't set up, use `https://github.com/lambdasistemi/haskell-gamechanger.git`.)

### 2. Generate the resolver URL

```
nix develop -c cabal run -v0 q2-probe -- \
  addr_test1qz6zuvdm0gu3q54pk50wjfjwyt4mwj6uaelzdfh9extxgn9jwpzyryhlkvscdgpkgefv78gkfa70p70tz04hjpeemjmsrd2jqm
```

This prints two lines: the script JSON for inspection, and a long
`https://beta-preprod-wallet.gamechanger.finance/api/2/run/...`
resolver URL. Capture the URL verbatim — do not re-encode or trim.

First build will take a few minutes; subsequent runs are instant.

### 3. Import the mnemonic into the wallet

Open the beta-preprod wallet in the laptop browser:

```
https://beta-preprod-wallet.gamechanger.finance/
```

Restore / import a wallet with this 12-word mnemonic:

```
rug silver nice monitor scorpion chase tunnel stone bleak time twelve enough
```

The wallet's first payment address must match:

```
addr_test1qz6zuvdm0gu3q54pk50wjfjwyt4mwj6uaelzdfh9extxgn9jwpzyryhlkvscdgpkgefv78gkfa70p70tz04hjpeemjmsrd2jqm
```

If it does not match, STOP and report: the wallet derives
differently than expected and every downstream assumption breaks.

No preprod ADA is needed. `signData` proves key custody only.

### 4. Start a listener on port 8080

In a second terminal, start whichever of these the laptop has:

```
nc -l 8080                    # BSD netcat; one-shot
nc -l -p 8080                 # GNU netcat variant
ncat -l 8080                  # nmap's ncat
python3 -m http.server 8080   # any laptop with Python; stays running
```

Keep it in the foreground so you can see the request line.

### 5. Paste the resolver URL into the browser

Paste the URL from step 2 into the address bar of the SAME
browser where the wallet is loaded. The wallet should show a
`signData` prompt asking to sign the hex bytes `68656c6c6f`
(ASCII `"hello"`) using the preprod address from step 3.

Approve the prompt.

### 6. Observe and report

There are exactly two possible outcomes.

**A — wallet redirects to `http://localhost:8080/?r=<payload>`.**

Your listener prints a request line like:

```
GET /?r=XQAAAAL... HTTP/1.1
Host: localhost:8080
```

Capture:
- The exact first line of the HTTP request.
- The value of the `r=` query parameter (it may be very long — keep
  the whole thing).

Report **Q2 = YES** with those captures. This is the happy path:
the plan for #25 proceeds as specified (one-shot Warp server on
an OS-assigned ephemeral port).

**B — anything else.**

Possible failure modes:

- Wallet refuses to sign with a visible error (screenshot /
  transcribe the exact text).
- Wallet signs but does not redirect; it renders the signature
  inside its own page (describe what it shows and where).
- Wallet redirects to a *different* URL (report the URL).
- Browser blocks the redirect with a security warning (transcribe
  the warning verbatim, including the browser name/version).
- Listener never receives anything and the wallet tab just sits.

Report **Q2 = NO** with the specific failure mode. This pivots
the plan to copy-paste or rendered-result delivery.

### 7. Cleanup

```
# stop the listener (Ctrl-C if python server)
# optionally remove the cloned worktree
```

## Reporting format

Write the report back to the work-machine agent by either:

1. Editing
   `specs/007-haskell-client-cli/q2-result.md` on this branch and
   pushing, OR
2. Pasting the report into the conversation with the user, who
   will relay it.

Template:

```markdown
# Q2 result

**Outcome**: YES | NO
**Browser**: Chrome 128 / Firefox 123 / Brave 1.60 / ...
**Wallet version**: (from the wallet's about page if visible)
**Derived address matched expected**: yes | no
**Listener tool**: nc / ncat / python http.server

## Captured evidence

(If YES)
- First line of HTTP request:
  `GET /?r=XQAAAAL... HTTP/1.1`
- Length of `r=` payload: <N> bytes
- First 80 chars of payload: `XQAAAAL...`

(If NO)
- Wallet behavior: <description>
- Verbatim error text: <quote>
- Screenshot path or URL (if taken): <link>

## Notes

(Anything unexpected — wallet popups, extension prompts,
certificate warnings, timing.)
```

## Hard constraints

- **Do NOT** modify `scripts/q2-probe.hs`, the cabal file, or the
  spec unless the user explicitly asks. Your job is to run the
  probe and report.
- **Do NOT** commit the mnemonic to any repo. It's already in the
  public record of this conversation as a probe-only throwaway;
  do not amplify that further.
- **Do NOT** push anything except a `q2-result.md` file if the
  user approves.
- If the address in step 3 does not match, STOP and report. Do
  not attempt to re-derive or guess.

## If you are blocked

Report the specific blocker (nix not installed, port in use,
wallet extension unavailable, mnemonic mismatch, etc) and wait
for direction. Do not improvise around it — every deviation
changes what Q2 actually answered.
