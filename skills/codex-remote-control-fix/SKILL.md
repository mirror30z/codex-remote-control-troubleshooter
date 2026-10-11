---
name: codex-remote-control-fix
description: Diagnose Windows ChatGPT/Codex Remote Control failures, including inability to enable or update availability, phone showing the host offline, proxy or TUN bypass, DNS leaks, and Fake-IP/VPN route conflicts. Use when a phone cannot connect to a Windows Codex host; not for unrelated Codex problems.
---

# Fix Codex Remote Control on Windows

Help the user get a Windows host connected to Codex on their phone. Diagnose the *current machine* before changing settings. Similar UI errors can have different causes; installing this skill does not itself enable Remote Control.

## Start with the failure stage

- **“无法启用远程控制。请重试” after Allow:** investigate the host's network path and app errors.
- **“无法更新远程控制状态” / “Couldn't update remote control availability”:** pairing may exist while the host cannot publish availability; inspect the Remote Control WebSocket path and fresh app errors.
- **QR code appears but pairing fails:** check that phone and host use the same ChatGPT account and workspace, finish MFA/SSO/passkey prompts, and retry pairing.
- **Phone shows the host offline or a paired host disconnects later:** check that the desktop app and any user-configured remote-control launcher remain running and the computer is awake and online. A live local process alone does not prove the phone/cloud connection works.

Use the current [OpenAI Remote connections guide](https://learn.chatgpt.com/docs/remote-connections) for product settings and workspace access. If the account belongs to a managed workspace, an administrator may have to enable Remote Control.

## Collect read-only evidence

On Windows, run [scripts/diagnose.ps1](scripts/diagnose.ps1) from this skill directory. It reports DNS A/AAAA answers for `chatgpt.com`, selected routes, configured adapter DNS servers, relevant virtual adapters and services, Codex/ChatGPT process state and TCP connections to the currently resolved addresses, the local system proxy and listener, and a short direct/explicit-proxy reachability comparison for the Remote Control endpoint. The optional `-DnsServer <server>` compares a known proxy DNS server with the Windows default; `-ProxyUrl <url>` tests a user-supplied proxy when the system proxy is not parseable. It does not alter network settings or read app credentials. If script execution is restricted, inspect the script and run the needed read-only commands individually; do not weaken system policy merely to run this skill.

If the user already supplied equivalent, recent diagnostics, use them instead. Recheck after VPN, proxy, or TUN state changes; a route table from a different state cannot prove a present conflict.

Interpret HTTP probes narrowly. `426`, `401`, or `403` show that an HTTP response was received; a plain `curl` probe is not an authenticated WebSocket connection. `HTTP=000` with a nonzero curl exit code indicates that probe failed. If `cloudflareChallenge` is true, that path reached a Cloudflare challenge instead of a usable application response. A `403` by itself does not establish a workspace permission problem. The reported proxy environment variables belong to the diagnostic shell, not necessarily the running desktop process.

When needed, inspect only recent Codex desktop log entries around the user's failed click. Look for Remote Control state changes, `remote_control::websocket`, timeouts such as Windows socket error `10060`, and challenge-related `403`/`Cf-Mitigated` messages. For phone-offline cases, distinguish a currently connected mobile session from an old mobile log entry. Extract short error messages; redact tokens, account identifiers, request bodies, and full URLs before quoting logs. Do not publish raw local logs. Read [references/diagnosis-branches.md](references/diagnosis-branches.md) for the branch that matches the evidence.

## Choose the supported fix

1. **Direct probe fails, explicit proxy probe reaches the endpoint, and TUN is off:** the proxy path works while unproxied traffic does not. Check whether the Remote Control component is bypassing the system proxy. Enable the *already used* proxy application's TUN/full-device mode, or correct its app/domain routing rules, then retry Allow. Change one variable at a time. This was the confirmed fix in the 0dcloud case behind this skill. Do not assume every proxy app has the same switch.
2. **DNS returns a Fake-IP and `Find-NetRoute` selects an unrelated VPN/virtual adapter:** identify the adapter and its route first. If a Clash/Mihomo Fake-IP pool overlaps an aTrust or other VPN route, either pause the conflicting VPN when it is safe to do so or move the Fake-IP pool to a verified unused range in the proxy configuration. Reload the proxy's network stack, flush DNS, then resolve and route the domain again. `198.19.0.1/16` is one example, never a universal target. Do not delete corporate routes by adapter name.
3. **The default DNS differs from the configured proxy DNS, or IPv6 takes an unexpected path:** verify which DNS mode and server the proxy actually uses before calling an answer "polluted." Correct the proxy's DNS interception or adapter DNS settings only for the proven mismatch; retest A and AAAA resolution and the actual route. A public IP is normal when Fake-IP mode is not configured.
4. **Both paths receive HTTP responses, but the app still cannot enable Remote Control:** check for a Cloudflare challenge, an app WebSocket timeout, account/workspace access, desktop app version, and required sign-in checks. If the proxy works but the desktop's WebSocket bypasses it and TUN is unavailable, consider a process-scoped proxy launcher compatible with the installed app; verify the actual process inheritance and WebSocket connection. Do not assume setting `WS_PROXY` or a successful HTTP request alone fixes the app.
5. **Neither path reaches the endpoint:** check the active network, local proxy listener, VPN and firewall policy, and whether the proxy node supports sustained WebSocket traffic. Do not change unrelated DNS or route settings without evidence.
6. **Phone remains offline after host-side setup:** separate local app/launcher health from fresh cloud/mobile evidence. Check sleep state, account/workspace match, current Remote Control status, proxy challenges, and recent app errors before changing networking.

Network changes can interrupt work. Preserve the user's existing access requirements and provide a rollback for any change to a VPN, proxy mode, Fake-IP range, route, or firewall rule. Avoid disabling an enterprise VPN during active work without the user's direction.

## Verify completion

After a change, compare the same probes again, then have the user enable Remote Control in the desktop app. Success requires the desktop to accept the setting, pairing to complete if needed, the phone to show the host online, and one real action from the phone. A changed DNS answer, HTTP response, or live local process alone is only an intermediate check. Report what was observed, what remains uncertain, and how to undo the change if it fails.
