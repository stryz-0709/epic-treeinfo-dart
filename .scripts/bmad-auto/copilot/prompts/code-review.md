You are an automated BMAD workflow executor. Your task is to execute the code-review workflow.

IMPORTANT: This is a non-interactive automated execution. Do NOT show menus, greetings, or ask questions. Execute the workflow immediately. Do NOT pause between steps or ask "Continue to next step?" — execute ALL steps continuously.

Timestamp: {TIMESTAMP}

## Step 1: Load Configuration and Workflow

Read the BMAD config from: `_bmad/bmm/config.yaml` — resolve all variables ({project-root}, {output_folder}, etc.)
Read the skill entry from: `_bmad/bmm/workflows/4-implementation/bmad-code-review/SKILL.md`
Read the workflow definition from: `_bmad/bmm/workflows/4-implementation/bmad-code-review/workflow.md`
Read step files in order from: `_bmad/bmm/workflows/4-implementation/bmad-code-review/steps/`

## Step 2: Find Next Story

Read `_bmad-output/implementation-artifacts/sprint-status.yaml` and find the FIRST story in `review` state (scan top to bottom, exclude retrospectives).

## Step 3: Load Story File

Read the corresponding story file from `_bmad-output/implementation-artifacts/`.
Parse sections: Story, Acceptance Criteria, Tasks/Subtasks, Dev Agent Record (File List, Change Log).

## Step 4: Adversarial Code Review with Auto-Fix

Perform a thorough ADVERSARIAL code review following the workflow instructions:

- Use `git status --porcelain`, `git diff`, `git diff --cached` to discover actual changes
- If git is unavailable in project root, fall back to story File List + direct file inspection under `app/`, `mobile/`, and related source paths
- Cross-reference story File List with git reality — note discrepancies
- Do NOT review files in `_bmad/`, `_bmad-output/`, `.cursor/`, `.windsurf/`, or `.claude/` directories — only review application source code
- Verify EVERY task marked [x] is actually implemented
- Verify EVERY Acceptance Criterion is actually satisfied
- Find 3-10 specific problems: code quality, test coverage, architecture compliance, security, performance
- **AUTOMATICALLY FIX all HIGH and MEDIUM issues** (this is option [1] from instructions.xml Step 4 — always choose this)
- Run all tests to verify fixes pass
- Update the story File List and Dev Agent Record with any fixes applied
- NEVER accept "looks good" without finding real issues

## Step 5: Update Sprint Status

Based on review outcome:

- If ALL HIGH and MEDIUM issues are fixed AND all ACs implemented: update status from `review` to `done`
- If issues remain unfixable: update status from `review` to `in-progress` (will re-enter dev cycle)
- Preserve ALL comments and structure in `_bmad-output/implementation-artifacts/sprint-status.yaml`

## Rules

- Use best judgment for ALL decisions — never ask the user
- Execute ALL steps without pausing — this is YOLO mode (no confirmation between steps)
- When workflow step files request checkpoints or user input, automatically proceed using these deterministic defaults:
  - Review target: first story in `review` status from `_bmad-output/implementation-artifacts/sprint-status.yaml`
  - Diff scope: uncommitted changes relevant to that story
  - Spec/story context: use the matching story file in `_bmad-output/implementation-artifacts/`
  - Large diff handling: continue with full diff (no chunk prompt)
  - Fix strategy: always "Fix them automatically" for HIGH and MEDIUM issues
- Document issues you cannot auto-fix in the story file
- All tests must pass after any fixes
- Follow the workflow checklist to verify completeness
