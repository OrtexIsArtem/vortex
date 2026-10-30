# Behavior

## Keys
- «+» opens the form: the value first (pasted, hidden; the eye shows it, to check what was pasted, until the window closes), the name Claude writes as {{name}}, a note for Claude and how long the key lives: 1 hour, until the end of the day, or for good (the default).
- What the key is shows as soon as it is pasted, told by how the value starts: PostgreSQL, MySQL, MongoDB, Redis, GitHub, Anthropic, OpenAI, Slack, AWS, Stripe, JWT, private key, link, or a token or password.
- A name left empty is the kind's («postgres», «github»…), numbered when taken; a name has Latin letters, digits, dots, dashes and underscores, no spaces, and is unique in any case.
- A row shows the kind, how long the key lives ("for good", "until 18:40") and when a command last ran with it, and the note.
- On hover: "Copy the name" copies «name (Vortex)», enough for Claude, which learns the keys from Vortex; the eye shows the value under the row for 20 s, with "Copy", until the window closes or another tab shows; the bin deletes the key.
- Showing a value asks for no Touch ID: on an unlocked Mac it could be had through Claude anyway. What keeps it safe is that Claude never gets it and asks first in each session.
- A copied value and the connect command are marked concealed, so clipboard histories, Vortex's own too, leave them out.
- Deleting shows "Key deleted · Undo" for 5 s; a new change makes the deletion final.
- A key whose time is up deletes itself, also while Vortex was closed (at the next launch).

## Claude
- Until Claude Code has connected once, the tab shows how: one command that removes an earlier `vortex` and adds this one with `--scope user`, copied whole with "Copy"; its token is not shown.
- Claude gets two tools: `keys` lists names, kinds, notes and expiry, never values; `run` runs a shell command with {{name}} where a value goes.
- The command runs in the user's shell with the environment their terminal has, `.zshrc` included (only the login profile if the shell doesn't answer in 10 s), in the folder Claude gives (else the home folder), with no input; it is stopped after 60 s unless Claude asks for up to 180, with everything it started.
- Only what the terminal's shell exports carries over, not its aliases, functions or options; the shell is asked again after a startup file changes (also through a link, or under ZDOTDIR), after 10 minutes, or after a command isn't found.
- A value goes in as a shell variable, so it is never part of the command's text; the output comes back with every value replaced by {{name}}, also as tools print it by accident: URL-encoded the usual ways, in base64, escaped in JSON, and a connection URL's password alone or as an HTTP Basic header. A part of a value, or one encoded on purpose, is not caught.
- A command not found (exit code 127) comes back with a hint for Claude.
- While a command runs, other programs of the user can see a value: in the tool's arguments (`psql "{{db}}"`) and in the environment of tools not from Apple. The approval stops programs that use the MCP token, not ones watching processes.
- A name Claude writes that no key has gets an error listing the keys there are.
- The first use of a key in a Claude session waits for "Allow": the notch shows a key and the name and flashes, each request has a notification of its own whose "Allow" and "Deny" answer that request, and the tab shows the request with the folder and the command, scrolling past a few lines with a fade and the number of lines; past 200 lines (or 20,000 characters) only its start is shown, and the card says so.
- Allowed, the key works for the rest of that session without asking; "Deny", or no answer in 90 s, gives Claude an error that says so. Waiting and running stay under the 5 minutes Claude Code waits for an answer.
- Claude giving a request up (Esc, or closing its connection) takes it away from the notch and the tab; a command it gave up is stopped. Either way Claude gets «Cancelled.».
- A request never asks macOS for permission to notify: without Notifications macOS drops the notification and the request waits in the tab.
- A request answered, given up or over takes its notification out of Notification Center; so does the feature starting, for requests of a run before.
- After Vortex restarts, Claude Code's session goes on as a new one: its keys are asked for again, and it needs no reconnecting. It is named Claude Code, as its own name went with the old one.
- Vortex does not decide what Claude may do with a key: Claude is told to ask the user before changing data.
- Turning the feature off, or a new port, ends every session and the requests waiting in them, and stops the commands still running (Claude gets «Cancelled.»); so does Vortex quitting.
- Vortex keeps no log of uses: Claude Code shows every command in its own history, and a key shows when a command last ran with it (a command stopped while running counts).

## Onboarding step (Claude Code)
- `makeOnboardingStep()` gives the shell the step "Claude Code": "Let Claude run commands with your saved keys without ever seeing their values. Skip this if you don't use Claude Code."; the footer says it can be done later in the Keys tab.
- "Connect" is enabled only while the server listens, and hidden when it failed to start: the step then shows the Keys card's "Claude can't reach the keys" with the port, the reason and "Pick another port in Settings › Features › Keys".
- Connect first asks the user's shell (zsh, bash or fish) only for its PATH, between two `__vortex_claude_path__` lines (5 s): what startup files print before them is never read.
- Vortex then looks for `claude` itself: in each absolute PATH directory, then ~/.local/bin, ~/.claude/local (an old install .zshrc reaches by an alias), /opt/homebrew/bin and /usr/local/bin.
- It runs only an absolute path to an existing executable file named `claude`, checked before the run; none found reads as not installed.
- The connect command then runs with that path (25 s). Both go through CommandClient, as Keys' `run`, non-interactive (`shell -c`), so nothing lands in shell history.
- The whole step stops 30 s after Connect on the clock, the shell's first start included: the run is stopped and the failure line shows exit code 143.
- In QA, put an executable `claude` in the run's folder and script the PATH: `sim shell match="printenv PATH" stdout=<marker>\n<that folder>\n<marker>`; unscripted, nothing is found, which reads as not installed.
- The token goes in the environment (`VORTEX_MCP_TOKEN`), never into the command Vortex builds, the screen, the logs, QA's state or snapshots; output is never kept.
- That guards Vortex's own outputs only: while it runs, the user's other programs can see the token in the shell's environment and in `claude`'s arguments, and Claude Code then keeps it in ~/.claude.json.
- Success: "Added to Claude Code ✓ — start a new Claude Code session to use your keys.", saved as `addedToClaudeCode`.
- `claude` missing: "Claude Code isn't installed" with the link to claude.com/claude-code; any other failure, the time limit included: one fixed line with the exit code. Both add "Copy command" (concealed) and "Run it in Terminal".
- A client connected before (`hasConnected`) or connected now shows "Connected ✓"; then, or after a success (also from before a relaunch, which shows the success line), the main "Connect" becomes a quiet "Connect again".
- "Connect again" shows the spinner and its result like "Connect".
- The step is done (`onboardingStepsDone` gets `secrets`) on success, on `hasConnected`, or while a session is live; checked at start too.
- In a QA run, 47823 (the user's own Vortex) counts as taken: Settings refuses it, and a port of 47823 found in secrets.json is never served on; the status says "Not running: Port 47823 is taken".
- While Vortex is blocked (a required permission is off), the MCP server goes on, and a request can be answered only from its notification, as the window doesn't open.
