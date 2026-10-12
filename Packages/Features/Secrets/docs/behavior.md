# Behavior

## Keys
- «+» opens the form: the value first (pasted, hidden; the eye shows it, to check what was pasted, until the window closes), the name Claude writes as {{name}}, a note for Claude and how long the key lives: 1 hour, until the end of the day, or for good (the default).
- What the key is shows as soon as it is pasted, told by how the value starts: PostgreSQL, MySQL, MongoDB, Redis, GitHub, Anthropic, OpenAI, Slack, AWS, Stripe, JWT, private key, link, or a token or password.
- A name left empty is the kind's («postgres», «github»…), numbered when taken; a name has Latin letters, digits, dots, dashes and underscores, no spaces, and is unique in any case.
- A row shows the kind, how long the key lives («безстроково», «до 18:40») and when a command last ran with it, and the note.
- On hover: «Копіювати ім'я» copies «name (Vortex)», enough for Claude, which learns the keys from Vortex; the eye shows the value under the row for 20 s, with «Копіювати», until the window closes or another tab shows; the bin deletes the key.
- Showing a value asks for no Touch ID: on an unlocked Mac it could be had through Claude anyway. What keeps it safe is that Claude never gets it and asks first in each session.
- A copied value and the connect command are marked concealed, so clipboard histories, Vortex's own too, leave them out.
- Deleting shows «Ключ видалено · Скасувати» for 5 s; a new change makes the deletion final.
- A key whose time is up deletes itself, also while Vortex was closed (at the next launch).

## Claude
- Until Claude Code has connected once, the tab shows how: one command that removes an earlier `vortex` and adds this one with `--scope user`, copied whole with «Копіювати»; its token is not shown.
- Claude gets two tools: `keys` lists names, kinds, notes and expiry, never values; `run` runs a shell command with {{name}} where a value goes.
- The command runs in the user's shell with the environment their terminal has, `.zshrc` included (only the login profile if the shell doesn't answer in 10 s), in the folder Claude gives (else the home folder), with no input; it is stopped after 60 s unless Claude asks for up to 180, with everything it started.
- Only what the terminal's shell exports carries over, not its aliases, functions or options; the shell is asked again after a startup file changes (also through a link, or under ZDOTDIR), after 10 minutes, or after a command isn't found.
- A value goes in as a shell variable, so it is never part of the command's text; the output comes back with every value replaced by {{name}}, also as tools print it by accident: URL-encoded the usual ways, in base64, escaped in JSON, and a connection URL's password alone or as an HTTP Basic header. A part of a value, or one encoded on purpose, is not caught.
- A command not found (exit code 127) comes back with a hint for Claude.
- While a command runs, other programs of the user can see a value: in the tool's arguments (`psql "{{db}}"`) and in the environment of tools not from Apple. The approval stops programs that use the MCP token, not ones watching processes.
- A name Claude writes that no key has gets an error listing the keys there are.
- The first use of a key in a Claude session waits for «Дозволити»: the notch shows a key and the name and flashes, each request has a notification of its own whose «Дозволити» and «Відхилити» answer that request, and the tab shows the request with the folder and the command, scrolling past a few lines with a fade and the number of lines; past 200 lines (or 20,000 characters) only its start is shown, and the card says so.
- Allowed, the key works for the rest of that session without asking; «Відхилити», or no answer in 90 s, gives Claude an error that says so. Waiting and running stay under the 5 minutes Claude Code waits for an answer.
- Claude giving a request up (Esc, or closing its connection) takes it away from the notch and the tab; a command it gave up is stopped. Either way Claude gets «Cancelled.».
- A request answered, given up or over takes its notification out of Notification Center; so does the feature starting, for requests of a run before.
- After Vortex restarts, Claude Code's session goes on as a new one: its keys are asked for again, and it needs no reconnecting. It is named Claude Code, as its own name went with the old one.
- Vortex does not decide what Claude may do with a key: Claude is told to ask the user before changing data.
- Turning the feature off, or a new port, ends every session and the requests waiting in them, and stops the commands still running (Claude gets «Cancelled.»); so does Vortex quitting.
- Vortex keeps no log of uses: Claude Code shows every command in its own history, and a key shows when a command last ran with it (a command stopped while running counts).
