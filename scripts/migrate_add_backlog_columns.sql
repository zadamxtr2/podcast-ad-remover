-- Migration: Add intelligent backlog processing columns
-- Adds priority tracking for automatic backlog episode selection

-- Add priority column to episodes table (nullable for backward compatibility)
ALTER TABLE episodes ADD COLUMN backlog_priority INTEGER DEFAULT NULL;

-- Add timestamp to track when backlog was last checked per subscription
ALTER TABLE subscriptions ADD COLUMN last_backlog_checked_at TIMESTAMP DEFAULT NULL;

-- Create index on backlog_priority for efficient sorting during queue processing
CREATE INDEX IF NOT EXISTS idx_episodes_backlog_priority 
ON episodes(backlog_priority, status, pub_date) 
WHERE backlog_priority IS NOT NULL;
