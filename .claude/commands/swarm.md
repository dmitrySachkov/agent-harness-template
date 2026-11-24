---
description: Split a list of work into independent parallel tasks and write the plan for swarm-worktree.sh launch
argument-hint: <the tasks, in your own words>
---

Plan parallel tasks from this request: $ARGUMENTS

You are the dispatcher. You plan; you do not start the tasks, create folders, write contracts or edit project code here.

1. Read `CLAUDE.md`, `docs/architecture.md` and `tasks/lessons.md`. For each piece of work, find the files it will most likely touch (use the `Explore` subagent for a broad search). A guess is fine, but say it is a guess.
2. Cut the request into tasks. One task = one contract = one agent in its own checkout. Do not split a vertical slice whose parts depend on each other: that is one task (it can use work packages inside). Do not merge unrelated work into one task.
3. Find the dependencies, pair by pair. The plan is a graph: a task either can start now, or comes after other tasks.
   - two tasks that edit the same source file cannot run in parallel: the second comes `after:` the first (or join them into one task);
   - a task that needs the result of another one (a port, a type, a screen) comes `after:` it;
   - shared files that many tasks only append to (`tasks/lessons.md`, a table in `docs/architecture.md`, a composition root) do not make a dependency, but name them: the human will see a merge conflict there;
   - keep the graph honest and small: a dependency you cannot explain in one line is not a dependency. No circles.
4. Write `tasks/.swarm-plan`, one line per task, tasks that can start now first:
   `name | what needs to be done`
   `name | after: other-name, another-name | what needs to be done`
   - `name`: lowercase letters, digits and dashes, short (it becomes the folder `../<repo>-<name>` and the branch `task/<name>`);
   - `after:` lists names from this same plan. `launch` starts a task only when everything it comes after is merged; the human runs `launch` again after each `finish`;
   - the last field is handed to `/task` in the new checkout word for word, so it must stand on its own: the outcome, the known constraints, the files you found. One line, no line breaks. For a task with `after:`, say what it may rely on from the earlier task;
   - lines starting with `#` are comments: put the reason for each `after:` there. Never write a line starting with `+`: that mark means "merged" and belongs to the script.
   If `tasks/.swarm-plan` already exists, show it and ask before overwriting: it may hold tasks that are still running or waiting.
5. **Stop.** Show the human the graph as a table: name, comes after, one-line outcome, expected files, risk of overlap. Say which tasks start at once and which wait. Then the next step, exactly:
   `./scripts/swarm-worktree.sh launch`  (the human runs it in their own terminal; it creates the checkouts of the ready tasks and opens a window with `/task` in each)
   then `./scripts/swarm-worktree.sh approve` for Gate 1, `status` to see the graph, and, when tasks are committed, `./scripts/swarm-worktree.sh finish` followed by `launch` again for the tasks that were waiting.

Rules:
- Never run `scripts/swarm-worktree.sh` yourself: it works outside this folder, and that is the human's action.
- More than three tasks ready at once: say that it is your recommendation to start with three, and why (each one needs a contract read and a receipt read by the same human).
- If the request is really one task, say so and suggest plain `/task` instead of a plan.
