---
name: codex-remote-control-fix
description: Diagnose Windows ChatGPT/Codex Remote Control setup failures, including “无法启用远程控制”, proxy or TUN bypass, and Fake-IP/VPN route conflicts. Use when a phone cannot connect to a Windows Codex host; not for unrelated Codex problems.
---

# Fix Codex Remote Control on Windows

Help the user get a Windows host connected to Codex on their phone. Diagnose the *current machine* before changing settings. Similar UI errors can have different causes; installing this skill does not itself enable Remote Control.

## Start with the failure stage

- **“无法启用远程控制。请重试” after Allow:** investigate the host's network path and app errors.
- **QR code appears but pairing fails:** check that phone and host use the same ChatGPT account and workspace, finish MFA/SSO/passkey prompts, and retry pairing.
- **Paired host disconnects later:** check that the desktop app remains running and the computer is awake and online.

Use the current [OpenAI Remote connections guide](https://learn.chatgpt.com/docs/remote-connections) for product settings and workspace access. If the account belongs to a managed workspace, an administrator may have to enable Remote Control.

## Collect read-only evidence

On Windows, run [scripts/diagnose.ps1](scripts/diagnose.ps1) from this skill directory. It reports DNS A answers for `chatgpt.com`, their selected Windows routes, relevant virtual adapters and services, the local system proxy, and a short reachability comparison for the Remote Control endpoint. It does not alter network settings or read app credentials. If script execution is restricted, inspect the script and run the needed read-only commands individually; do not weaken system policy merely to run this skill.

If the user already supplied equivalent, recent diagnostics, use them instead. Recheck after VPN, proxy, or TUN state changes; a route table from a different state cannot prove a present conflict.

Interpret HTTP probes narrowly. `426`, `401`, or `403` show that an HTTP response was received; a plain `curl` probe is not an authenticated WebSocket connection. `HTTP=000` plus a timeout or reset indicates that probe failed. A `403` in the app's own log may come from the service or an intermediary and does not alone establish a workspace permission problem.

When needed, inspect only recent Codex desktop log entries around the user's failed click. Extract error codes and short messages for `remote_connections.connection_state_changed`; redact tokens, account identifiers, and full URLs before quoting logs. Do not publish raw local logs.

## Choose the supported fix

1. **Direct probe fails, explicit proxy probe reaches the endpoint, and TUN is off:** the proxy path works while unproxied traffic does not. Check whether the Remote Control component is bypassing the system proxy. Enable the *already used* proxy application's TUN/full-device mode, or correct its app/domain routing rules, then retry Allow. Change one variable at a time. This was the confirmed fix in the 0dcloud case behind this skill. Do not assume every proxy app has the same switch.
2. **DNS returns a Fake-IP and `Find-NetRoute` selects an unrelated VPN/virtual adapter:** identify the adapter and its route first. If a Clash/Mihomo Fake-IP pool overlaps an aTrust or other VPN route, either pause the conflicting VPN when it is safe to do so or move the Fake-IP pool to a verified unused range in the proxy configuration. Reload the proxy's network stack, flush DNS, then resolve and route the domain again. `198.19.0.1/16` is one example, never a universal target. Do not delete corporate routes by adapter name.
3. **Both paths reach the endpoint yet the app still cannot enable Remote Control:** verify the account/workspace, desktop app version, required sign-in checks, and workspace Remote Control policy using the official guide. Review a fresh app error before assigning a cause.
4. **Neither path reaches the endpoint:** check the active network, local proxy health, VPN and firewall policy, and whether the proxy node supports sustained WebSocket traffic. Do not change unrelated DNS or route settings without evidence.

Network changes can interrupt work. Preserve the user's existing access requirements and provide a rollback for any change to a VPN, proxy mode, Fake-IP range, route, or firewall rule. Avoid disabling an enterprise VPN during active work without the user's direction.

## Verify completion

After a change, compare the same probes again, then have the user enable Remote Control in the desktop app. Success requires a pairing code or QR code, the phone appearing as connected, and one real action from the phone. A changed DNS answer or an HTTP response alone is only an intermediate check. Report what was observed, what remains uncertain, and how to undo the change if it fails.
