# Evidence-based diagnosis branches

Use this reference only for the branch suggested by the current symptom and diagnostic report. The bundled script is read-only; it cannot prove that an authenticated Remote Control WebSocket or mobile session succeeded.

## Probe interpretation

The script disables curl's default configuration and explicitly selects direct or proxy mode, overriding the diagnostic shell's `NO_PROXY`. The direct label means curl does not use an explicit proxy; an active TUN or VPN may still capture it. HTTP CONNECT responses alone do not prove the upstream application answered. No curl, skipped probes, PAC-only configuration, DNS query errors, and route query errors are missing evidence. `socks5` uses local name resolution while `socks5h` asks the proxy to resolve the destination, so differing results may involve both DNS and routing.

DNS and connection results are snapshots. HTTPS proxies can resolve names differently from Windows; local proxy connections and helper processes are not covered by the narrow Codex/ChatGPT-to-resolved-address filter. A custom `-Endpoint` changes the queried hostname; the default path is internal and may change between app versions. Verify a `404` or `410` against current app evidence before treating it as a networking failure.

## Change and rollback record

Before changing settings, record the exact previous value and chosen scope. Apply one change, rerun the same diagnostics in the new state, and verify the desktop and phone. If the result worsens or does not help, restore the previous state before trying another branch.

| Change | Record before changing | Rollback |
| --- | --- | --- |
| TUN or app/domain routing | Existing mode and affected rules | Restore mode/rules and reload the proxy |
| Fake-IP address pool | Original pool and conflicting route evidence | Restore pool, reload proxy stack, flush cached DNS, retest |
| Adapter DNS or interception | Adapter identity, automatic/manual DNS state, servers/rules | Restore original automatic/manual state and rules |
| Process-scoped launcher | Original shortcut/launcher and per-process environment | Restore launcher and reopen app after saving active work |
| Temporary VPN pause | Whether that VPN is needed for current remote/work access | Reconnect VPN and verify previous access |

Avoid changes that would disconnect the only remote session. If a required enterprise policy blocks the tested path, report the evidence to the administrator rather than deleting routes or bypassing controls.

## DNS mismatch or IPv6 path

Compare the Windows default A and AAAA answers with `-DnsServer` only when the user's proxy exposes a known DNS listener. `127.0.0.1` is not a universal Clash DNS address. Confirm the proxy's DNS mode before treating a public answer as suspicious; Fake-IP is optional. A mismatch can come from an adapter DNS server, IPv6 DNS, a PAC configuration, or the proxy's own rules. Inspect the active adapter's DNS and route, then change only the proven faulty rule. Do not disable IPv6 or point all adapters at loopback as a blanket fix; that can break other networks.

For a Fake-IP answer, use `Find-NetRoute -RemoteIPAddress <actual A address>` and compare `interfaceIndex` with the current adapters. The presence of `198.18.*` or `198.19.*` alone does not prove a route conflict. A process connection in `SynSent` to the currently resolved address adds evidence of a stalled path; an `Established` connection does not prove Remote Control itself is healthy.

## Explicit proxy works, application WebSocket fails

Check the actual proxy host and port, the local listener, and a direct versus explicit-proxy probe. If only the explicit proxy succeeds, check whether the application process uses the proxy, whether TUN captures its traffic, and whether the proxy supports WebSocket traffic. Shell `HTTP_PROXY` and `WS_PROXY` values are only the shell's environment. They do not show which variables the already-running desktop process inherited.

If TUN conflicts with an enterprise VPN or cannot be enabled, a dedicated process-scoped proxy launch may be an option. Inspect the installed app and launcher before using one. Keep changes limited to that app process, preserve the existing `CODEX_HOME` and built-in `openai` provider, and avoid rewriting thread history or changing the system proxy merely to solve this branch. Reopen the app through the verified launch path when it is safe to interrupt active work, then test Remote Control itself. HTTP `426` or `403` is not proof that WebSocket negotiation or authorization worked.

## HTTP 403 and Cloudflare challenge

Distinguish ordinary HTTP status from a response bearing `Cf-Mitigated: challenge`. A challenge can block a proxy route even though DNS and TCP checks succeed. Compare direct and explicit-proxy results; if only one route is challenged, select a working route or proxy node according to the user's network requirements, then retry. Do not infer account entitlement from a challenge response. If both routes reach the service without a challenge, inspect a recent application error and the official Remote Control requirements.

## Paired host offline or status update fails

Separate four pieces of evidence: desktop application running, any user-configured `codex remote-control` process or launcher running, a recent host-to-cloud connection, and a current phone-to-host session. A status file, scheduled task, or process listing proves only local state. Check whether the computer sleeps, whether the app has an active sign-in, whether the phone uses the same account/workspace, and whether the app reports an availability or WebSocket error. Do not mistake the desktop app's SSH connections screen for phone Remote Control setup.

If the user has a custom launcher, inspect its shortcut target, proxy settings, and current logs before changing it. A shortcut that points directly to a versioned Microsoft Store AppX path can become stale after an update. Preserve the user's existing task data. Do not change `model_provider`, delete enrollment data, or edit SQLite history to repair an offline indicator.

## Evidence and privacy

Report the exact failing stage, current test result, next smallest reversible change, and a rollback. Before sharing diagnostics publicly, remove account identifiers, local usernames, device names, private network topology, cookies, tokens, and raw application logs. Keep a time stamp so a route report collected before a TUN/VPN change is not treated as current.
