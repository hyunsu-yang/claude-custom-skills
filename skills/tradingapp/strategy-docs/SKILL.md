---
name: strategy-docs
description: Manages trading strategy documentation lifecycle — updating CURRENT_STRATEGY.md, creating numbered change logs, incrementing versions, and syncing user guides. Use when strategy logic changes, when updating plan_doc/ files, or when the user mentions strategy documentation, version tracking, or change logs.
---

# Strategy Documentation Management

## Latest Strategy Reference

- Single source of truth: `plan_doc/strategy_reference/CURRENT_STRATEGY.md`
- Update this file whenever strategy logic changes (engine, sub-strategies, filters, risk management, regime detection, etc.)

## Strategy Change Log

- Create a new numbered change log: `plan_doc/{N}_strategy_update_{version}_{YYYYMMDD}.md`
- Contains **only the changes** (not the full strategy)
- Check the latest numbered file in `plan_doc/` to determine the next number

## Version Tracking

- Increment the version in `CURRENT_STRATEGY.md` version history table
- Format: v{major}.{minor} (e.g., v4.3 -> v4.4)

## Plan Files

- `.plan.md` files in `plan_doc/` are implementation plans — **do not edit** after implementation
- `.md` reference files in `plan_doc/` are documentation — update as needed

## User Guide Sync

When strategy changes affect user-facing settings (new parameters, preset values, UI controls, strategy behavior descriptions), update:

- `user_guide/USER_GUIDE.md`: Strategy tab (4.4), preset table (4.2), risk tab (4.5), recommended settings (7), FAQ (8)
- `user_guide/SETTINGS_EXAMPLES.md`: JSON examples and setting rationale tables

If only internal logic changes (no new UI settings, no visible behavior change), user guide update is not required.
