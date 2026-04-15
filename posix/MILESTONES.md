# POSIX Layer Milestones

## Milestone A — Bootstrap (Complete)

- API/header scaffold created
- backend model established
- initial smoke validation in place

## Milestone B — Core IO + FS Coverage (Complete)

- file I/O wrappers
- descriptor helpers
- filesystem metadata + traversal
- link/symlink support

## Milestone C — Semantics Hardening (Complete)

**Goal:** Match predictable POSIX-like behavior for shell/editor workloads.

Deliverables:

1. Behavior matrix + error model ✅
2. Expanded edge-case tests ✅
3. ABI implementation guide ✅

## Milestone D — Toolchain Readiness (Planned)

**Goal:** Make the layer practical for incremental BusyBox/editor ports.

Deliverables:

1. utility wrappers needed by parser + file-edit loops
2. stronger tty assumptions documentation
3. integration examples for host and kernel backends

## Milestone E — First Real Port (Planned)

**Goal:** Run first non-trivial CLI tool on top of wrapper.

Candidate targets:

- `cat`/`ls` bundle (preferred first)
- minimal shell loop
- nano-like file open/edit/save core
