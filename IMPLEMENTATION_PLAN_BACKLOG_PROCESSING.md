# Intelligent Backlog Processing Implementation Plan

## Problem Statement
Currently, when a user sets a feed to automatically process the N most recent episodes (e.g., 5), once those N episodes are consumed, older unprocessed episodes remain in `unprocessed` status and must be manually triggered for download. This implementation adds intelligent backlog processing that automatically keeps N episodes available by downloading older episodes when fewer than N are completed.

## Current Architecture Analysis

### Key Files
- `app/core/processor.py`: Main processing logic
  - `check_feeds()`: Fetches latest N episodes, marks them `'pending'`
  - `process_queue()`: Processes all `'pending'` episodes
  - `run_loop()`: Main loop calling check_feeds every interval_minutes

- `app/infra/repository.py`: Database operations
  - EpisodeRepository with status management (`pending`, `unprocessed`, `completed`)
  - JobRepository for claiming/processing queue items

### Current Flow
1. **Feed Check**: Fetches latest N episodes → marks as `'pending'` → rest stay `'unprocessed'`
2. **Queue Processing**: Processes all `'pending'` episodes concurrently (up to limit)
3. **Completion**: After processing, RSS regenerated
4. **Gap**: Once user consumes all N episodes, older ones sit in `'unprocessed'` until manual trigger

## Implementation Plan

### Phase 1: Database Schema Changes

#### 1.1 Add Priority Column to Episodes Table
```sql
ALTER TABLE episodes ADD COLUMN backlog_priority INTEGER DEFAULT NULL;
```
- `NULL` = no backlog priority (manual download only)
- Lower integer = higher priority for automatic processing
- Only applies to episodes within retention limit range

#### 1.2 Track Last Backlog Check Per Subscription
Add to subscriptions table:
```sql
ALTER TABLE subscriptions ADD COLUMN last_backlog_checked_at DATETIME DEFAULT NULL;
```
- Used to track when backlog was evaluated
- Helps prevent duplicate processing attempts

### Phase 2: Core Logic Changes

#### 2.1 Modify `check_feeds()` in processor.py

**New Logic Flow:**
```python
async def check_feeds(self, subscription_id: int = None, limit: int = 5):
    # ... existing feed fetching logic ...
    
    for sub in subs:
        try:
            episodes = FeedManager.parse_episodes(sub.feed_url)
            
            # Calculate retention limit
            actual_limit = sub.retention_limit if sub.retention_limit else limit
            
            completed_count = self.ep_repo.count_completed(sub.id)
            backlog_needed = max(0, actual_limit - completed_count)
            
            for i, ep_data in enumerate(episodes):
                ep_data['subscription_id'] = sub.id
                
                # Determine status based on position and backlog needs
                if i < actual_limit:
                    # Within retention limit
                    
                    if backlog_needed > 0:
                        # Need to fill backlog - prioritize older episodes
                        should_be_pending = (
                            completed_count + i >= len(episodes) - backlog_needed
                        )
                        
                        if should_be_pending and ep_data['status'] != 'completed':
                            ep_data['status'] = 'pending'
                            # Calculate priority based on pub_date
                            ep_data['backlog_priority'] = self._calculate_backlog_priority(
                                ep_data['pub_date'], 
                                completed_count, 
                                backlog_needed
                            )
                            
                        backlog_needed -= 1
                    else:
                        # No backlog needed - mark only newest as pending
                        if i < (actual_limit - completed_count):
                            ep_data['status'] = 'pending'
                    
                else:
                    ep_data['status'] = 'unprocessed'
                
                # Try to create episode
                created = self.ep_repo.create_or_ignore(ep_data)
                
                if created and ep_data.get('status') == 'pending':
                    logger.info(f"Backlog queued: {ep_data['title']}")
                    
        except Exception as e:
            logger.error(f"Error checking feed {sub.feed_url}: {e}")
```

#### 2.2 Implement Priority Calculation Method

Add to `Processor` class:
```python
def _calculate_backlog_priority(self, pub_date: datetime, completed_count: int, 
                                 backlog_needed: int) -> int:
    """
    Calculate priority for backlog episodes.
    
    Logic:
    - Oldest episodes within retention limit get highest priority
    - Priority decreases as we approach newer episodes
    - Never prioritize already-completed episodes
    
    Returns: integer (lower = higher priority, 1 = highest)
    """
    if backlog_needed <= 0:
        return None  # No backlog priority needed
    
    # Find the cutoff date for oldest episode in retention limit
    completed_episodes = self.ep_repo.get_completed_by_subscription(
        completed_count - 1, sub.id
    )
    
    if not completed_episodes:
        # If no completed episodes, prioritize from oldest available
        all_episodes = FeedManager.parse_episodes(sub.feed_url)
        if all_episodes:
            cutoff_date = all_episodes[-1]['pub_date']  # Oldest in feed
        else:
            return None
    
    episode_date = pub_date or datetime.min
    cutoff_date = cutoff_date or datetime.max
    
    # Calculate position from oldest within retention limit
    position_from_oldest = (cutoff_date - episode_date).days
    
    # Higher position = lower priority
    priority = max(1, min(100, position_from_oldest // 7 + completed_count))
    
    return priority
```

#### 2.3 Add Helper Method to Count Completed Episodes

Add to `EpisodeRepository`:
```python
def count_completed(self, subscription_id: int) -> int:
    """Count episodes with status='completed' for a subscription."""
    with get_db_connection() as conn:
        row = conn.execute(
            "SELECT COUNT(*) as count FROM episodes "
            "WHERE subscription_id = ? AND status = 'completed'",
            (subscription_id,)
        ).fetchone()
        return row['count'] if row else 0
```

#### 2.4 Update `process_queue()` to Respect Priority

Modify the claim logic in `process_queue()`:
```python
async def process_queue(self):
    # ... existing setup code ...
    
    claimed = self.job_repo.claim_due(capacity)
    if not claimed:
        return
    
    # Sort claimed episodes by priority (NULL last, then ascending)
    claimed.sort(key=lambda x: (x.get('backlog_priority') is None, 
                                x.get('backlog_priority', 999)))
    
    for ep_dict in claimed:
        # ... existing processing logic ...
```

#### 2.5 Add Backlog Check Hook in run_loop()

After feed check, optionally trigger backlog re-evaluation:
```python
async def run_loop(self):
    # ... existing code ...
    
    await self.check_feeds()
    
    # Optional: Re-evaluate backlog immediately if enabled
    from app.web.router import get_global_settings
    db_settings = get_global_settings()
    enable_backlog = db_settings.get('enable_intelligent_backlog', False)
    
    if enable_backlog:
        await self._recheck_backlog_needs()
    
    last_feed_check = datetime.now()
```

Add new method:
```python
async def _recheck_backlog_needs(self):
    """Re-evaluate backlog after initial processing to promote next candidates."""
    subs = self.sub_repo.get_all()
    
    for sub in subs:
        completed_count = self.ep_repo.count_completed(sub.id)
        actual_limit = sub.retention_limit or 5
        
        if completed_count < actual_limit:
            # Backlog still needed - check if any unprocessed should be promoted
            backlog_needed = actual_limit - completed_count
            
            # Get oldest unprocessed episodes within limit
            all_episodes = FeedManager.parse_episodes(sub.feed_url)
            
            for i, ep_data in enumerate(all_episodes):
                if ep_data['status'] == 'unprocessed':
                    if (completed_count + i >= len(all_episodes) - backlog_needed):
                        # This episode should be pending now
                        self.ep_repo.update_status_by_guid(
                            sub.id, 
                            ep_data['guid'], 
                            'pending', 
                            condition_status='unprocessed'
                        )
                        logger.info(f"Promoted to backlog: {ep_data['title']}")
                    
                    if completed_count + i >= len(all_episodes) - backlog_needed:
                        break
```

### Phase 3: Configuration Settings

#### 3.1 Add Global Settings

Add to `app_settings` table (or use existing app_settings row):
- `enable_intelligent_backlog`: INTEGER (0/1, default 0 for backward compatibility)
- `backlog_check_interval_minutes`: INTEGER (default same as check_interval_minutes)

#### 3.2 Subscription-Specific Settings (Optional Future Enhancement)
Future consideration: Allow per-subscription backlog settings:
- `backlog_enabled`: BOOLEAN
- `backlog_aggressiveness`: INTEGER (1-5, how eagerly to fill backlog)

### Phase 4: API Endpoints Updates

#### 4.1 Add Backlog Status Endpoint (Optional)

New endpoint to check backlog status per subscription:
```python
@app.get("/api/subscriptions/{subscription_id}/backlog")
async def get_backlog_status(subscription_id: int):
    sub = self.sub_repo.get_by_id(subscription_id)
    if not sub:
        raise HTTPException(status_code=404, detail="Subscription not found")
    
    completed_count = self.ep_repo.count_completed(sub.id)
    retention_limit = sub.retention_limit or 5
    
    return {
        "subscription": sub.title,
        "completed_episodes": completed_count,
        "retention_limit": retention_limit,
        "backlog_needed": max(0, retention_limit - completed_count),
        "unprocessed_in_backlog": self._count_unprocessed_in_backlog(sub.id)
    }
```

### Phase 5: Testing Scenarios

#### 5.1 Test Cases to Implement

1. **Initial Setup**: 
   - Feed has 20 episodes, retention_limit=5
   - All 5 newest should be pending, rest unprocessed
   
2. **After Consuming All 5**:
   - User downloads/listens to all 5 completed episodes
   - System should detect gap and promote oldest unprocessed episode

3. **Rapid Consumption**:
   - User consumes episodes faster than they arrive
   - System should backfill from older episodes within retention limit

4. **Manual Download Coexistence**:
   - Manual downloads should not interfere with backlog processing
   - Already-completed episodes should never be re-queued for backlog

5. **Feed Refresh During Backlog**:
   - If new episodes arrive while backlog is being filled, oldest should still be prioritized

### Phase 6: Migration Strategy

#### 6.1 Database Migration Script

Create `scripts/migrate_add_backlog_columns.sql`:
```sql
-- Add priority column to episodes (nullable for backward compat)
ALTER TABLE episodes ADD COLUMN backlog_priority INTEGER DEFAULT NULL;

-- Add last check timestamp to subscriptions
ALTER TABLE subscriptions ADD COLUMN last_backlog_checked_at DATETIME DEFAULT NULL;
```

#### 6.2 Backward Compatibility

- Default `enable_intelligent_backlog = 0` preserves current behavior
- Existing installations must opt-in via settings update
- No data loss or breaking changes

### Phase 7: Documentation Updates

1. **README.md**: Add section describing intelligent backlog feature
2. **Documentation/DECISIONS.md**: Record architectural decision for automatic backlog processing
3. **Documentation/CHANGELOG.md**: Document new feature and configuration options
4. **Web UI**: Add toggle in subscription settings to enable/disable intelligent backlog

### Phase 8: Rollout Plan

1. **Phase 1 (Week 1)**: Implement core logic with opt-in flag
2. **Phase 2 (Week 2)**: Add monitoring/logging for backlog activity
3. **Phase 3 (Week 3)**: Optimize priority algorithm based on user feedback
4. **Phase 4 (Week 4)**: Make feature enabled by default after stabilization

### Phase 9: Performance Considerations

- Priority calculation is O(1) per episode - no performance impact
- Database queries are indexed on pub_date and status
- Backlog check runs same frequency as feed check (configurable)
- No additional API calls or external dependencies

### Phase 10: Edge Cases to Handle

1. **Episode deleted mid-backlog**: 
   - RSS update removes episode, system should skip it
   
2. **Processing failure during backlog fill**:
   - Failed episodes remain unprocessed until next check
   - System won't get stuck in infinite loop
   
3. **Subscription paused/deactivated**:
   - Backlog processing stops automatically when subscription inactive
   
4. **Multiple concurrent processor instances**:
   - SQLite row-level locking prevents race conditions
   - Priority calculation is idempotent

## Summary of Changes

### Files to Modify:
1. `app/infra/repository.py` - Add count_completed() method
2. `app/core/processor.py` - Implement backlog logic in check_feeds(), priority calculation, run_loop updates
3. `app/infra/database.py` - Database migration for new columns
4. `app/web/router.py` - Optional backlog status endpoint

### Files to Create:
1. `scripts/migrate_add_backlog_columns.sql` - Migration script
2. Update config documentation for new settings

### Configuration Changes:
- Add 2 new global settings (enable_intelligent_backlog, backlog_check_interval_minutes)
- Default values preserve backward compatibility

## Next Steps

1. Review and approve this implementation plan
2. Implement Phase 1 (database schema changes)
3. Implement Phase 2 (core logic in processor.py)
4. Add configuration options
5. Write tests for each scenario
6. Update documentation
7. Deploy with opt-in flag
8. Monitor and optimize based on user feedback
