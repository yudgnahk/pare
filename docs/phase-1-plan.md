# Clean My Mac (Pure Swift) - Plan

## Goal
Build a native macOS cleaning app in pure Swift that safely finds and removes reclaimable storage with a focus on developer, designer, and video workflows.

## Product Direction
- Native stack: SwiftUI + AppKit where needed.
- Core loop: scan, review, clean.
- Safety-first: trash-before-delete, clear explanations, exclusions, and dry-run mode.
- Persona packs: Developer, Designer, Video Builder.

## Architecture
- App layer: onboarding, permissions, dashboard, result review, cleanup flow.
- ScanEngine: rule-based discovery and size estimation.
- SafetyEngine: protected paths, confidence levels, and pre-delete checks.
- CleanupEngine: transactional cleanup with logs and restore path.
- Profiles: presets + user-customized rules.
- Scheduler (later phase): periodic reminders/scans.

## Delivery Phases

### Phase 0 - Discovery and Guardrails
Define platform support, distribution model, deletion policy, protected paths, and persona cleanup matrix.

### Phase 1 - Core Scanner MVP
Implement async scan engine, baseline rules (caches/temp/logs/browser cache subset), and result model with category/path/size/last-used/confidence.

### Phase 2 - Persona Packs
Add focused rule sets for developers, designers, and video builders.

### Phase 3 - Safe Cleanup Engine
Implement trash pipeline, transaction logs, and undo flow.

### Phase 4 - UX and Trust
Dashboard, explainability, dry-run, quick clean, deep clean confirmations.

### Phase 5 - Performance and Reliability
Incremental scan metadata cache, robust cancellation/progress, and large-folder performance testing.

### Phase 6 - QA, Security, Release
Test matrix, protected-path regression checks, notarization, and diagnostics export.
