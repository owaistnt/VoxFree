# Convention For Archiving

## History Files

History files document the investigation and resolution of issues, features, or changes. They serve as a reference for future developers to understand the evolution of the codebase and avoid repeating the same troubleshooting steps.

### Naming Convention

```
YYYY-MM-DD-Title.md
```

- **YYYY-MM-DD**: Date the work was done
- **Title**: Descriptive title using kebab-case (lowercase with hyphens)
- **Examples**:
  - `2026-06-21-STT-Not-Recording-and-Clipboard-Image-Paste.md`
  - `2026-06-15-Deb-Commands-Not-Working.md`

---

All history files are stored in the `docs/history/` folder.

---

## Issue Files

Used when documenting bugs, failures, or unexpected behavior.

### Structure

#### Overview

One-paragraph summary of what was broken and when.

#### Symptoms

Bulleted list of observable behavior. What did the user see? What was logged?

#### Root Cause Analysis

Explanation of why the problem occurred. Include code snippets, file paths, line numbers where relevant.

#### Approaches Tried

A table documenting every attempt and its result:

| # | Approach | Result |
|---|----------|--------|
| 1 | Description of attempt | ✅ Fixed / ❌ Did not fix / ⚠️ Partial |

This prevents future developers from trying the same dead ends.

#### Final Fix

What actually solved the problem. Include code diffs or before/after snippets where helpful.

#### Related Files

A table of files changed and what was modified.

| File | Change |
|------|--------|

---

## Feature Files

Used when documenting new features or enhancements.

### Structure

#### Problem

What gap or limitation does this feature address? Why is it needed?

#### Envisioning

How should the feature work from the user's perspective? Include expected behavior, UI flow, and edge cases.

#### Solution

Technical implementation details. What was built and how.

#### Related File

A table of files created or modified.

| File | Purpose |
|------|---------|
