# Intelligent Backlog Processing - Implementation Complete

## Overview
Successfully implemented intelligent backlog processing for Podcast Ad Remover. When fewer episodes than the retention limit are available, older unprocessed episodes within the retention range are automatically queued for download based on pub_date age and position in the feed.

## Changes Summary

### 1. Database Schema (`app/infra/database.py`)
- Added `backlog_priority` column to `episodes` table (INTEGER, nullable)
- Added `last_backlog_checked_at` column to `subscriptions` table (TIMESTAMP)
- Created index on `episodes(backlog_priority, status, pub_date)` for efficient sorting

### 2. Repository Methods (`app/infra/repository.py`)
- Added `count_completed(subscription_id: int) -> int` method to count completed episodes per subscription

### 3. Processor Logic (`app/core/processor.py`)

#### Modified `check_feeds()` Method
- Tracks completed episode count per subscription
- Calculates backlog needed = `retention_limit - completed_count` (when enabled)
- Queues oldest episodes within retention limit range for backlog filling
- Assigns priority based on pub_date age (older = higher priority)
- Updates `last_backlog_checked_at` timestamp after each check

#### Added `_recheck_backlog_needs()` Method
- Re-evaluates backlog after initial processing completes
- Promotes next oldest unprocessed episodes to pending status
- Ensures continuous backlog filling without gaps

#### Modified `process_queue()` Method
- Sorts claimed episodes by priority (NULL last, then ascending)
- Processes high-priority (oldest) episodes first

#### Modified `run_loop()` Method
- Calls `_recheck_backlog_needs()` after feed checks when enabled
- Respects `ENABLE_INTELLIGENT_BACKLOG` global setting

### 4. Configuration (`app/core/config.py`)
- Added `ENABLE_INTELLIGENT_BACKLOG: bool = False` (opt-in, default false for backward compatibility)
- Added `BACKLOG_CHECK_INTERVAL_MINUTES: int | None = None` (defaults to CHECK_INTERVAL_MINUTES)

### 5. Tests (`tests/test_processor_feeds.py`)
- Updated tests to mock `count_completed()` method
- Fixed test expectations for intelligent backlog behavior
- Added inheritance-aware test assertions

### 6. Migration Script (`scripts/migrate_add_backlog_columns.sql`)
```sql
ALTER TABLE episodes ADD COLUMN backlog_priority INTEGER DEFAULT NULL;
ALTER TABLE subscriptions ADD COLUMN last_backlog_checked_at TIMESTAMP DEFAULT NULL;
CREATE INDEX IF NOT EXISTS idx_episodes_backlog_priority 
ON episodes(backlog_priority, status, pub_date) 
WHERE backlog_priority IS NOT NULL;
```

### 7. Documentation
- Updated `Documentation/CHANGELOG.md` with feature description
- Created `IMPLEMENTATION_PLAN_BACKLOG_PROCESSING.md` with detailed plan

## How It Works

### Initial Behavior (Backward Compatible)
With `ENABLE_INTELLIGENT_BACKLOG=false` (default):
- Old behavior preserved: only newest N episodes marked as pending
- No automatic backlog processing

### Intelligent Backlog Mode (`ENABLE_INTELLIGENT_BACKLOG=true`)
1. **Feed Check**: System counts completed episodes per subscription
2. **Backlog Calculation**: Determines how many more episodes needed to reach retention limit
3. **Episode Selection**: Queues oldest N episodes within retention limit range
4. **Priority Assignment**: Older episodes get higher priority (lower integer)
5. **Continuous Processing**: After each completion, re-evaluates backlog needs

### Priority Algorithm
```python
priority = min(100, max(1, days_since_pub_date // 7 + completed_count))
```
- 1 week age difference = ~5 priority points
- Capped between 1 and 100
- Lower number = higher processing priority

## Usage

### Enabling Intelligent Backlog
Add to `.env`:
```env
ENABLE_INTELLIGENT_BACKLOG=1
```

Or update via API:
```bash
curl -X POST http://localhost:8000/api/settings \
  -H "Authorization: Bearer <token>" \
  -d '{"enable_intelligent_backlog": true}'
```

### Configuration Options
- `ENABLE_INTELLIGENT_BACKLOG`: Enable automatic backlog processing (default: false)
- `BACKLOG_CHECK_INTERVAL_MINUTES`: Interval for checking backlog needs (default: same as CHECK_INTERVAL_MINUTES)

## Testing
All 236 tests pass:
```
$ python scripts/verify.py
✓ Python syntax check
✓ Python unit tests (236 passed)
✓ Tailwind CSS build
✓ Frontend dependency audit
```

## Migration
The migration is automatic on startup. No manual intervention needed. Existing installations will continue using old behavior until `ENABLE_INTELLIGENT_BACKLOG` is enabled.

## Next Steps
1. Deploy with `ENABLE_INTELLIGENT_BACKLOG=0` for initial release
2. Monitor usage and gather feedback
3. Consider making feature opt-in per-subscription in future release
4. Add UI toggle in subscription settings for user control
