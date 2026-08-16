class SearchQuery(BaseModel):
    query: str
    
@router.post("/search")
async def search_podcasts(q: SearchQuery, user = Depends(require_auth)):
    return await PodcastSearcher.search(q.query)

@router.post("/episodes/{id}/track-listen")
async def track_listen(id: int, user = Depends(require_auth)):
    """Increment listen count for an episode."""
    ep_repo = EpisodeRepository()
    ep = ep_repo.get_by_id(id)
    if not ep:
        raise HTTPException(status_code=404, detail="Episode not found")
    
    ep_repo.increment_listen_count(id)
    return {"status": "tracked", "episode_id": id}

# Admin-only: Manually reprocess episode and optionally reset listen count
@router.post("/admin/episodes/{id}/reprocess", response_model=dict)
async def admin_reprocess_episode(
    id: int, 
    skip_transcription: bool = False, 
    reset_listen_count: bool = True, 
    user = Depends(require_admin)
):
    """Admin endpoint to manually reprocess an episode.
    
    By default, this resets listen_count to 0 so the episode can be processed again.
    Set reset_listen_count=False to preserve the current count but still requeue.
    """
    from app.core.processor import Processor
    
    # Check if already processing (safety check)
    status = ep_repo.get_status(id)
    if status == 'processing':
        return {
            "status": "ignored", 
            "reason": "already_processing"
        }
    
    # Optionally reset listen count to 0 for reprocessing
    if reset_listen_count:
        with get_db_connection() as conn:
            cursor = conn.execute("UPDATE episodes SET listen_count = 0 WHERE id = ?", (id,))
            if cursor.rowcount == 0:
                raise HTTPException(status_code=404, detail="Episode not found")
    
    # Reset status to pending with processing flags
    import json
    flags = {'skip_transcription': skip_transcription}
    flags_json = json.dumps(flags)
    
    ep_repo.reset_status(id, processing_flags=flags_json)
    ep_repo.update_status(id, "pending")
    
    # Queue for processing
    proc = Processor()
    await proc.process_queue()
    
    return {
        "status": "reprocessed", 
        "episode_id": id, 
        "message": f"Episode {id} queued for reprocessing. listen_count reset: {reset_listen_count}"
    }

