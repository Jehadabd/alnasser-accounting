## graphify

This project has a knowledge graph at graphify-out/ with god nodes, community structure, and cross-file relationships.

Rules:
- For codebase questions, first run `graphify query "<question>"` when graphify-out/graph.json exists. Use `graphify path "<A>" "<B>"` for relationships and `graphify explain "<concept>"` for focused concepts. These return a scoped subgraph, usually much smaller than GRAPH_REPORT.md or raw grep output.
- If graphify-out/wiki/index.md exists, use it for broad navigation instead of raw source browsing.
- Read graphify-out/GRAPH_REPORT.md only for broad architecture review or when query/path/explain do not surface enough context.
- After modifying code, run `graphify update .` to keep the graph current (AST-only, no API cost).
- Only open a source file once the graph has told you which one. Use `graphify path "A" "B"` to trace how two parts connect.

## Project brain (Obsidian)
My notes for this project live in:
  C:\Users\jihad\Documents\Brain\Projects\alnasser-accounting-edition\

At the start of every session:
1. Read `00 Overview.md` and `03 Status.md` before anything else.
2. Check `02 Decisions.md` before suggesting changes to how things work.
3. Use `01 Map.md` (and the Graphify graph) to find files instead of re-exploring the codebase.
4. Do not re-explore the codebase for facts already in these notes.

Keep notes short. Use [[wikilinks]] between notes. Never put passwords, API keys or license secrets in the notes.

## Before ending a session
When I say "wrap up" (or «لخّص الجلسة»):
- Update `03 Status.md`: what we did, what is half done, next step.
- Add any decision we made to `02 Decisions.md` with the date and why.
- Keep each update under 10 lines.

## Working with me
- Reply to me in Arabic.
- I build and run the app myself (`flutter run -d windows`, the `claude_*.bat` files); edit files and tell me what to run.
