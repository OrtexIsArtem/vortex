---
title: Keep Secrets and .env Files Away from Claude Code · Vortex
description: How to stop Claude Code from reading .env files, keep MCP tokens out of your repo, and let Claude use API keys on your Mac without seeing them.
heading: Keep secrets and .env files away from Claude Code
label: Secrets and Claude Code
published: 2026-11-01
updated: 2026-11-01
chapter: keys
faq:
  - q: Does Claude Code read .env files?
    a: >-
      It can. Reading files in your project needs no approval, `.env` included, unless a deny rule such as
      `Read(./.env)` blocks it. A `.claudeignore` file has no effect.
  - q: Is a deny rule enough to protect my .env file?
    a: >-
      Not on its own. It covers Claude’s file tools and commands such as `cat`, but not a script that opens the file
      itself. Turn on the sandbox too: macOS then enforces the same rules for the commands Claude runs in it.
  - q: Can Claude Code use an API key without seeing it?
    a: >-
      Yes. Claude Code’s sandbox can mask a token: commands see a placeholder, and its proxy puts the real value into
      HTTPS requests to hosts you allow. Vortex works with any command, database clients included: Claude writes
      `{{name}}`, and Vortex puts the value in and takes it back out of the output.
  - q: Where should I keep MCP server tokens on a Mac?
    a: >-
      Out of your repository. In a shared `.mcp.json`, reference an environment variable such as `${API_KEY}`, or
      let a `headersHelper` read the token from your keychain. A token added with `claude mcp add --header` is saved
      in `~/.claude.json`, unless you add the server with `--scope project`.
  - q: Does Vortex send my keys anywhere?
    a: >-
      No. Values stay in your login keychain, and Vortex never goes online by itself. Network traffic comes only from
      the commands Claude runs with your keys, after you allow them.
---

Claude Code can read the files in your project without asking, `.env` included, and the commands it runs see the API keys in your environment. This guide shows what Claude Code itself offers to keep secrets out of reach, where each option stops, and how Vortex lets Claude use a key without ever seeing it.

Everything about Claude Code here comes from [Anthropic’s documentation](https://code.claude.com/docs/en/settings) as of November 2026. Settings change between versions, so check the linked pages before you rely on one.

## The options at a glance

| Option | What it stops | What it doesn’t |
| --- | --- | --- |
| Deny rules | Claude reading a file with its own tools or `cat` | A script, or `grep -r`, reading it |
| Sandbox | Any command Claude runs reading what you deny | MCP servers and hooks; anything you don’t list |
| Sandbox `mask` | Commands seeing a token they send over HTTPS | Tools that bypass the proxy, like most database clients |
| Vortex Keys | Claude seeing a key it uses in a command | Claude seeing the output; other programs seeing the value while the command runs |

## Stop Claude Code from reading .env files

Add a deny rule to your settings. Claude Code then leaves matching files out of search results, refuses to read them, and won’t edit them. ([Settings reference](https://code.claude.com/docs/en/settings-reference#permissions-deny))

```json
{
  "permissions": {
    "deny": [
      "Read(./.env)",
      "Read(./.env.*)",
      "Read(./secrets/**)"
    ]
  }
}
```

- Put it in `.claude/settings.json` in your project and commit it, and your whole team gets it. Deny rules apply right away, even before anyone trusts the folder.
- Or put it in `~/.claude/settings.json`, and it applies in every project you open.
- `Read(.env)` matches a `.env` file at any depth under the folder you start Claude Code in. `Read(//**/.env)` matches one anywhere on your Mac.
- In `~/.claude/settings.json`, a path that starts with a single `/` points inside `~/.claude`, not into your project. Start paths there with `./`, `~/` or `//`.
- A `.claudeignore` file has no effect. Move its entries into deny rules.

Run `/status` in Claude Code to check that your settings file loaded.

### What a deny rule doesn’t stop

A `Read` rule covers Claude’s own file tools, the file commands it recognizes in Bash, such as `cat`, `head` and `tail`, and redirections such as `< .env`. It doesn’t cover a command that reads files without naming them, like `grep -r`, or a script that opens the file itself. ([Permissions](https://code.claude.com/docs/en/permissions#read-and-edit))

## Block secrets for every command with the sandbox

Claude Code has a sandbox for the commands it runs. It’s off by default: turn it on with `/sandbox`, or with `"sandbox": { "enabled": true }` in your settings. On a Mac it uses the system’s own Seatbelt framework, so there’s nothing to install. ([Sandboxing](https://code.claude.com/docs/en/sandboxing))

With the sandbox on, macOS itself enforces your `Read` deny rules for the commands Claude runs in it and for every process they start. That covers the `grep -r` and script cases above.

The sandbox can also block credential files and unset environment variables before each command:

```json
{
  "sandbox": {
    "enabled": true,
    "credentials": {
      "files": [{ "path": "~/.aws/credentials", "mode": "deny" }],
      "envVars": [{ "name": "GITHUB_TOKEN", "mode": "deny" }]
    }
  }
}
```

Know where it stops:

- It covers shell commands only. Claude’s file tools follow your deny rules instead, and MCP servers and hooks run outside it.
- Claude can retry a failed command outside the sandbox, which usually asks you first. `"allowUnsandboxedCommands": false` under `sandbox` turns those retries off.
- Sandboxed commands can still read most of your Mac, `~/.ssh` and `~/.aws/credentials` included, and they inherit your environment. Only what you list is blocked.

To strip credentials from the environment of the commands, hooks and local MCP servers Claude Code starts, sandboxed or not, set `CLAUDE_CODE_SUBPROCESS_ENV_SCRUB=1`. It recognizes a credential by its name or the shape of its value, and leaves GitHub tokens in place. ([Environment variables](https://code.claude.com/docs/en/env-vars))

## Keep MCP server tokens out of your repository

A remote MCP server often needs a token, and where the token ends up depends on how you add the server. ([MCP](https://code.claude.com/docs/en/mcp))

- `claude mcp add --header "Authorization: Bearer …"` saves it in `~/.claude.json`, in your home folder, with the default local scope or `--scope user`. With `--scope project`, it goes into the project’s `.mcp.json`.
- A project’s `.mcp.json` is meant to be committed, so keep the token out of it. Claude Code expands `${VAR}` and `${VAR:-default}` in a server’s `command`, `args`, `env`, `url` and `headers`, so the file can name a variable instead:

```json
{
  "mcpServers": {
    "api-server": {
      "type": "http",
      "url": "https://api.example.com/mcp",
      "headers": {
        "Authorization": "Bearer ${API_KEY}"
      }
    }
  }
}
```

On a Mac, a `headersHelper` can read the token from your keychain each time Claude Code connects, so it isn’t in any file. The command must print the headers as JSON:

```json
{
  "mcpServers": {
    "api-server": {
      "type": "http",
      "url": "https://api.example.com/mcp",
      "headersHelper": "printf '{\"Authorization\": \"Bearer %s\"}' \"$(security find-generic-password -s api-server-token -w)\""
    }
  }
}
```

Put the token in your keychain once with `security add-generic-password -a "$USER" -s api-server-token -w`, which asks for it. For a server in `.mcp.json`, Claude Code runs the helper only after you trust the project’s folder.

## Let Claude Code use an API key without seeing it

Deny rules and the sandbox keep a key away from Claude. Sometimes Claude needs the key, though: to query your database, or to call an API while it debugs. If you paste the key into the chat, or Claude reads it from a file or your environment, the key becomes part of the conversation.

Claude Code’s sandbox has one answer. With `"mode": "mask"`, a sandboxed command sees a placeholder, and the sandbox’s proxy puts the real token into requests to the hosts you allow. It needs TLS termination at the proxy, which is still experimental, and it works only for traffic that goes through the proxy. A database client that opens its own connection, as most do, can’t reach the network from inside the sandbox at all. ([Mask credentials](https://code.claude.com/docs/en/sandboxing#mask-credentials))

[Vortex](../) takes another route. It’s a free, [open-source](https://github.com/OrtexIsArtem/vortex) Mac app that lives in the notch, and its Keys feature runs the command for Claude:

- You store each key in Vortex under a name. The value stays in your login keychain.
- Claude Code writes `{{name}}` where the value goes and sends the command to Vortex through a local MCP server.
- Vortex runs the command in your shell, with the environment your terminal has, in the folder Claude gives. The value goes in as a shell variable, so it’s never part of the command’s text.
- The output comes back with each value replaced by `{{name}}`, also where a tool prints it URL-encoded, in base64 or escaped in JSON, and a connection URL’s password on its own or in an HTTP Basic header.
- The first time a Claude Code session uses a key, you allow it from the notch.

It works with the tools your terminal already has: `psql`, `mysql`, `mongosh`, `redis-cli`, `curl`, `gh`, `aws`. The MCP server listens only on 127.0.0.1, needs a token, and refuses requests from web pages. The rules it follows are in [the feature’s docs](https://github.com/OrtexIsArtem/vortex/blob/main/Packages/Features/Secrets/docs/behavior.md).

## Set up Vortex Keys for Claude Code

1. **Install Vortex.** It’s free, for macOS 14 or later on Apple silicon. [Download it below](#download). Vortex isn’t notarized by Apple, so the first launch takes one more step, shown there.
2. **Add a key.** Open Vortex, go to **Keys** and press **+**. Paste the value: a token, password or connection URL. Vortex shows what it is, such as PostgreSQL, GitHub token or OpenAI API key.
3. **Name it.** Claude writes the name as `{{name}}`. Leave it empty to use the kind’s name, such as `postgres` or `github`. Add a note for Claude if it helps, and choose how long the key lives: 1 hour, until the end of the day, or for good.
4. **Connect Claude Code once.** During Vortex’s setup, press **Connect** on the Claude Code page. Or open **Keys**, press **Copy** under “Connect Claude Code once” and run the command in Terminal. Once Claude Code has connected, that card goes away, and the command stays in **Settings › Features › Keys** as **Copy the connect command**. It adds Vortex to Claude Code for every project:

   ```text
   claude mcp remove --scope user vortex >/dev/null 2>&1; claude mcp add --transport http --scope user vortex http://127.0.0.1:47823/mcp --header "Authorization: Bearer <token>"
   ```

   Vortex fills in its own token, so copy the command from Vortex, not from here.
5. **Start a new Claude Code session.** Claude Code now has two tools from Vortex: `keys`, which lists your keys’ names, kinds and notes, never their values, and `run`, which runs a command with `{{name}}` in it.
6. **Ask Claude.** For example: “How many users are in the database? Use my postgres key in Vortex.” Claude writes a command like `psql "{{postgres}}" -c 'select count(*) from users'`. To point Claude at a key, hover over it in Vortex and press **Copy the name**: it copies `postgres (Vortex)`.
7. **Allow the key.** The first time a session uses a key, the notch shows its name and flashes, and a notification shows the command with **Allow** and **Deny**; the Keys tab shows it too, with the folder. Allow it, and the key works for the rest of that Claude Code session without asking. Deny it, or let 90 seconds pass, and Claude gets an error that says so.

Without notifications turned on, the request waits in the Keys tab. A command stops after 60 seconds, unless Claude asks for up to 180.

## What Vortex Keys doesn’t protect against

- **Claude sees what a command returns.** That’s your data: the rows from your database, the API’s response. Only the key is taken out.
- **A value encoded on purpose isn’t caught,** nor is a part of a value, nor a value shorter than 4 characters. If a command prints the key in a form Vortex doesn’t look for, Claude sees it.
- **Other programs on your Mac can see the value while a command runs:** in the tool’s arguments, as in `psql "{{postgres}}"`, and in the environment of tools not made by Apple. Allowing a key stops programs that use Vortex’s MCP token, not ones that watch processes.
- **Your OK counts for the whole session.** Once you allow a key, Claude can run other commands with it until the session ends. Vortex doesn’t judge what a command does; Claude is told to ask you before it changes data. To have Claude Code ask before every command it sends to Vortex, add an ask rule to your settings:

  ```json
  {
    "permissions": {
      "ask": ["mcp__vortex__run"]
    }
  }
  ```

- **Commands run with your access.** Vortex runs them in your own shell, outside Claude Code’s sandbox.
- **The MCP token lives in `~/.claude.json`.** A program that reads it can send Vortex commands too; each key still waits for your Allow.
- **Anyone at your unlocked Mac can see a value.** Showing it in Vortex asks for no Touch ID.

You can try the whole flow, Allow and Deny included, in [the Keys demo](../#keys) on the home page.
