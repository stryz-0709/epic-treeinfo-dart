You are an automated BMAD workflow executor. Your task is to execute the create-story workflow.

IMPORTANT: This is a non-interactive automated execution. Do NOT show menus, greetings, or ask questions. Execute the workflow immediately. Do NOT pause between steps or ask "Continue to next step?" — execute ALL steps continuously.

Timestamp: {TIMESTAMP}

## Step 1: Load Configuration and Workflow

Read the BMAD config from: `_bmad/bmm/config.yaml` — resolve all variables ({project-root}, {output_folder}, etc.)
Read the skill entry from: `_bmad/bmm/workflows/4-implementation/bmad-create-story/SKILL.md`
Read the workflow definition from: `_bmad/bmm/workflows/4-implementation/bmad-create-story/workflow.md`
Read the workflow template from: `_bmad/bmm/workflows/4-implementation/bmad-create-story/template.md`
Read the workflow checklist from: `_bmad/bmm/workflows/4-implementation/bmad-create-story/checklist.md`
Read discover inputs guidance from: `_bmad/bmm/workflows/4-implementation/bmad-create-story/discover-inputs.md`

## Step 2: Find Next Story

Read `_bmad-output/implementation-artifacts/sprint-status.yaml` and find the FIRST story in `backlog` state (scan top to bottom, exclude retrospectives).

## Step 3: Load and Analyze Context (Exhaustive)

Follow the bmad-create-story workflow + discover-inputs protocol:

- Read the corresponding epic file from `_bmad-output/planning-artifacts/`
- Read PRD, architecture docs, and any referenced project context artifacts
- Analyze previous story files for context continuity (patterns, conventions, decisions)
- Understand story requirements, acceptance criteria, and BDD scenarios

## Step 4: Create Story File

Follow the workflow instructions and template to create the story file in `_bmad-output/implementation-artifacts/` (root story location). The story file must include all acceptance criteria, tasks, subtasks, dev notes, and implementation guidance.

## Step 5: Update Sprint Status

Update `_bmad-output/implementation-artifacts/sprint-status.yaml` — change the story status from `backlog` to `ready-for-dev`. Preserve ALL comments and existing structure in the YAML file.

## Rules

- Use best judgment for ALL decisions — never ask the user
- Do NOT implement the story code — only create the story file
- Follow the workflow template precisely
- Execute ALL steps without pausing — this is YOLO mode (no confirmation between steps)
- When instructions.xml has `<ask>` tags, use best judgment instead of asking
- If blocking issues arise, document them in the story file and continue
