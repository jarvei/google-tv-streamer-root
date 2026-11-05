# Temporary root on the Google TV Streamer (kirkwood / MT8696) — without killing the system

Per-boot `uid=0` on a **Google TV Streamer** (`kirkwood`, MediaTek MT8696,
Android 14, kernel `5.15.180-android14-11-gf55c0c36ffcd-ab13512086`) using
**CVE-2026-43499 ("GhostLock")**, with the Android framework still alive.

This is not a new exploit. It documents a one-line change to the public
GhostLock wrapper that makes the difference between "root and a black screen"
and "root and a working TV".

## The problem

The published one-click wrapper sets:

```
GHOST_SELINUX_PRESERVE_INIT=0
```

With `0`, the exploit's first write (`W1`) puts eight zero bytes at the start of
`selinux_state`. That clears `enforcing` **and `initialized`**. The kernel then
believes no SELinux policy is loaded: `security_sid_to_context_core()` fails,
binder transactions return `EINVAL`, and `system_server` dies. `init` kills the
`zygote` process group and its `onrestart` fails on the missing security
context — the framework never comes back. The TV is left with no image and only
a power cycle recovers it (and that reboot loses the root, which is volatile).

## The fix

The exploit already ships the option; the wrapper just forces it off. With:

```
GHOST_SELINUX_PRESERVE_INIT=1
```

`W1` leaves `enforcing=0` but `initialized != 0`. SELinux stays **Permissive
with the policy loaded**, binder keeps working, `system_server` survives, and
the UI keeps running.

One line:

```bash
sed 's/GHOST_SELINUX_PRESERVE_INIT=0/GHOST_SELINUX_PRESERVE_INIT=1/' \
    ghostlock-kirkwood-oneclick.sh > ghostlock-preserve.sh
```

`scripts/apply-preserve-init.sh` does this and checks the result.

Verified on 2026-11-05: `id -u` = 0, `getenforce` = Permissive,
`system_server` alive, `Service window: found`, video playback running.

## Requirements

- Google TV Streamer on the same build/kernel as above, reachable over ADB:
  `adb connect <STREAMER_IP>:5555`.
- The original bundle: `ghostlock-kirkwood-oneclick.sh` from
  [yichen115/ghostlock-kirkwood](https://github.com/yichen115/ghostlock-kirkwood)
  (Apache-2.0). It is **not** redistributed here.
- A clean boot: `getenforce` = `Enforcing`, no previous agent.
- The bundle, `adb` and the device on the same LAN.

## Usage

```bash
# 1. apply the one-line change
./scripts/apply-preserve-init.sh ghostlock-kirkwood-oneclick.sh

# 2. push it
adb push ghostlock-preserve.sh /data/local/tmp/
adb shell 'chmod 755 /data/local/tmp/ghostlock-preserve.sh'

# 3. one attempt per clean boot
adb shell 'sh /data/local/tmp/ghostlock-preserve.sh \
    --perf-loops 60000 --settle-us 120000 --exec "id; getenforce"'
```

Wait for `ROOT AGENT READY`. **Do not restart `zygote` or `system_server`
afterwards**; if the shot fails, check that SELinux is still `Enforcing` before
retrying. The capture gate is flaky: `verdict=0` / `near=0` means the exploit
refused to write anything, so a retry on the same boot is safe. If SELinux is
left `Permissive` with no agent, reboot before trying again.

## Verification

`id` alone is not enough. Read a block device that only root can open:

```bash
adb shell '/data/local/tmp/.ghostlock-oneclick/kirkwood_root_sh \
  --name <abstract-from-root_agent_ready> --exec \
  "id; getenforce; dd if=/dev/block/by-name/boot_a bs=16 count=1 2>/dev/null | od -An -tx1"'
```

Expected: `uid=0(root)`, `Permissive`, and the `ANDROID!` magic
(`41 4e 44 52 4f 49 44 21`). Also check `pidof system_server` and
`service check window` (`Service window: found`).

## Re-root after a reboot

The root is **volatile** by design: bootloader locked, AVB green, no
persistent-root path. `scripts/reroot.sh` waits for the device, retries the
attempt while SELinux stays `Enforcing`, and verifies `uid=0` plus
`system_server`.

```bash
./scripts/reroot.sh          # waits for boot, up to 6 attempts
./scripts/reroot.sh --status # read-only state
```

## Rules

- One attempt per clean boot; if a partial write happens, reboot first.
- Do **not** kill the parked `ghostlock-lab` process: it holds the fake credential page.
- Do not update the OTA (`google_ota_automatic_download=0`); a fixed kernel kills the exploit.
- If `init` is wedged and `reboot`/`sys.powerctl` do not work, `echo b > /proc/sysrq-trigger` as root resets through the kernel.
- Do not try to relaunch `zygote` by hand: ART aborts on `BOOTCLASSPATH` / `No mainline framework library found`.

## Files

- `scripts/apply-preserve-init.sh` — applies the one-line change, verifies it.
- `scripts/reroot.sh` — re-root after a reboot, with retries and verification.
- `scripts/attach.sh` — reconnect to the running root agent and run a command.
- `docs/METODO-ROOT.es.md` — step-by-step method (Spanish).
- `docs/report.es.md` — analysis and evidence (Spanish).

## Credits and license

- Exploit and original bundle: [yichen115/ghostlock-kirkwood](https://github.com/yichen115/ghostlock-kirkwood),
  Apache-2.0. All credit for the primitive goes to its author.
- CVE-2026-43499: futex PI `remove_waiter()` stale waiter, fixed in 5.15.212+.
- The one-line `PRESERVE_INIT` finding, the scripts and the docs in this repo
  are released under the MIT license (see `LICENSE`).

Rooting your own hardware may void warranties and violate terms of service.
Use it on devices you own or are authorized to test.
