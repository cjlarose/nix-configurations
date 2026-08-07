---
name: hermes-ask
description: Ask Bingy (the hermes agent on ns1010301) a question or delegate a task via the LAN API server at http://10.0.0.5:8642. Wraps the API call, handles session naming for multi-turn continuity, and surfaces the response inline. Use when you want to delegate to or chat with Bingy without manual curl.
---

# hermes-ask

Ask the [[hermes]] agent (Bingy) a question or delegate a task via its HTTP API at
`http://10.0.0.5:8642`. The API server must be enabled (`API_SERVER_KEY` set in
`hermes.env`) and the [[hermes]] guest must be running.

> **Full reference:** [[Hermes API Server Setup and Protocol]] — complete endpoint
> surface, auth, multi-turn mechanics, alternatives that were ruled out, and security.

## Invocation

`/hermes-ask [--session <name>] <prompt>`

- **`--session <name>`** — name the conversation for multi-turn continuity; every call
  with the same name continues the SQLite-persisted session. Omit for one-shot.
- **`<prompt>`** — the message to send Bingy.

## Steps

### 1. Find the API key

Check in order:
1. `$HERMES_API_KEY` environment variable.
2. `/run/secrets/hermes-api-key` (agenix/sops path on ns1010301).
3. If neither is available, tell the user to set `HERMES_API_KEY` or provide the key
   value from `/var/lib/microvms/hermes/secrets/hermes.env` on ns1010301.

### 2. Send the request

For a **one-shot** call:

```bash
curl -s http://10.0.0.5:8642/v1/chat/completions \
  -H "Authorization: Bearer $HERMES_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"model": "hermes", "messages": [{"role": "user", "content": "<PROMPT>"}]}' \
  | jq -r '.choices[0].message.content'
```

For a **named session** (multi-turn), add the header:

```bash
  -H "X-Hermes-Session-Id: <SESSION_NAME>"
```

The `model` field is ignored by hermes — the agent always uses whatever is configured
in `config.yaml` (currently `anthropic/claude-sonnet-4-6`, `reasoning_effort: medium`).

### 3. Surface the response

Print Bingy's response directly. Do not summarize it unless the user asks for that.

### 4. If the request fails

Check:
- Is the [[hermes]] guest up? (`ssh cjlarose@10.0.0.5 systemctl is-active hermes-agent`)
- Is the API server enabled? (`API_SERVER_KEY` must be set in
  `/var/lib/microvms/hermes/secrets/hermes.env` on ns1010301.)
- Is port 8642 open on `enp0s11`? (The firewall rule should already be in place from
  commit `ae602ef`.)

## Notes

- The API server shares one agent process with the Discord bot. A conversation via this
  API is a separate session lane but shares the same memory, SOUL.md, and skills.
- The `terminal` tool is unsandboxed within [[Agent Sandbox Writable Paths]]. Treat the
  API key as a shell credential — anyone with it can run arbitrary commands as the
  hermes user.
- For async / long-running tasks, use `POST /v1/runs` (returns 202 + run_id
  immediately; poll `/v1/runs/{run_id}/events` for SSE lifecycle events). Not covered
  by this skill's default flow; extend if needed.
