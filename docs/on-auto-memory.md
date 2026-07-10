# On Auto-Memory

**Auto-memory is interventionist.**
It watches for corrections, rejections, and task completions, then interrupts the workflow to generate and persist a "memory" entry.
The trigger conditions are broad, and it typically fires on one-off situational corrections that have no long-term value.
Every time you say `No.`, `No, ...` and provide additional context, or press the ESC key, a prompt is injected by the harness that instructs Claude to pay close attention to whatever you say next because it likely contains clues about user preferences that should be saved as a memory.
The act of capturing becomes a task in itself — one that competes with the actual work you are trying to do, introduces its own failure modes, and pollutes future sessions with low-signal entries that the model then has to evaluate and potentially misapply.
In our experience, Claude is actually aware of this problem and will learn to ignore the memories section of the system prompt due to how noisy it often becomes — thereby also reducing the value of any legitimate memories created.

**The knowledge system is passive infrastructure.**
It sits on the hook layer, intercepts outbound search commands (recursive greps, find, and variants thereof), parses the query intent, and checks an indexed markdown knowledge base for matches.
When it finds relevant entries, it prepends them to the tool output — clearly labelled, alongside the original results that would have been returned regardless.
It does not ask the agent to stop and do anything. It does not create entries autonomously. It does not inject reminders or nag about its own usage.

The distinction is architectural, not cosmetic:

- **No interruption.** The agent never has to context-switch from its task to do bookkeeping. The hooks run in the execution layer, transparent to the conversation.
- **No false triggers.** It activates on search operations, which are precisely the moments when prior knowledge is relevant. A situational correction like "use that branch" never triggers it because no search command was issued.
- **No pollution.** Entries are curated, not auto-generated. The knowledge base doesn't accumulate low-quality entries from misinterpreted corrections.
- **No competition.** Because it augments tool output rather than injecting system reminders, it adds context exactly where the agent is already looking. It works with attention rather than against it.

The auto-memory pattern assumes the agent is the right judge of what's worth remembering, in the moment, under task pressure, which contradicts known best practices.
This makes the agent perform worse over time by adding meta-work and injecting accumulated slop.
The knowledge system improves performance over time by reducing redundant exploration and by actually baking the maintenance of created entries into the tool itself (at the time of writing, memories are a dumping ground on a conveyor belt — good and bad all get deleted based on age, in background with no user input, this is why Claude mysteriously unlearns things).


## On Timing and the Maintenance Queue

As files are changed or created during a session, hooks automatically build out a maintenance queue — a log of what shifted and what might warrant a new or updated knowledge entry.
This happens passively, with zero agent involvement. The queue doesn't trigger anything. It accumulates. The decision to act on it is collaborative and context-aware.
If the session was grueling and the context window is spent, the queue waits.
If a task wraps cleanly and there's headroom, the agent can review the queue and create entries that would genuinely serve future sessions — with the human in the loop on what's worth keeping.

This is the inverse of the auto-memory model in every respect.
Auto-memory demands the agent make curation decisions at the worst possible time: mid-task, under cognitive load, with no way to distinguish a durable insight from a momentary correction.
The queue system defers that decision to the right time, with the right participant, under the right conditions.
Setting the agent up to make the right decision when the time comes is always better than interrupting it to nag about crossing a bridge it hasn't reached yet.
