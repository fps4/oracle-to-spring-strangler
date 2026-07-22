# Generator prompt — dependency-map.md

Paired output: `assessment/dependency-map.md`
Run with: any agentic coding assistant with read access to `legacy/`
(this repo used Claude Code; see `assessment/agents/README.md`).

---

You are performing the assessment phase of an Oracle-to-Spring modernization.
Read every file under `legacy/db/init/` and `legacy/ords/modules.sql`.

Produce `assessment/dependency-map.md` with three Mermaid diagrams plus a
CRUD matrix, derived strictly from the code (no invented edges):

1. **Package-to-table CRUD matrix** — a markdown table: rows = packages
   (plus ORDS handlers as a pseudo-module for direct table access), columns =
   the 10 tables, cells = C/R/U/D letters. Below it, a Mermaid graph of the
   same edges labeled with the operations.
2. **Package-to-package calls** — Mermaid graph (note the PKG_ORDERS ->
   PKG_PRICING pricing call and what it implies for migration ordering).
3. **Endpoint-to-package routing** — Mermaid graph: each ORDS endpoint to the
   package procedure it invokes; flag any endpoint that bypasses packages and
   reads tables directly (that asymmetry matters for the wave plan).

For every edge, cite the source line(s) in a reference list at the bottom.
Close with a short **"What this means for sequencing"** paragraph: which
module is safe to migrate first purely on dependency grounds, and why.
End the file with an `## Architect review` footer left EMPTY for the human pass.
