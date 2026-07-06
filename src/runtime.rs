use once_cell::sync::Lazy;
use tokio::runtime::Runtime;

/// Shared tokio runtime. v1 is synchronous: every database call does a
/// `block_on` here. The async integration with ludi (yield/resume) will
/// replace the block, not the API — see docs/adr/0002-sync-first.md.
pub static RT: Lazy<Runtime> = Lazy::new(|| {
    tokio::runtime::Builder::new_multi_thread()
        .enable_all()
        .build()
        .expect("fredy: failed to create tokio runtime")
});
