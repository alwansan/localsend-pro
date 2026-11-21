use flutter_rust_bridge::frb;
use std::fs::File;
use std::sync::Mutex;

/// Holds an OS file-description lock for the duration of one Pro receiver
/// writer. On Linux/Android this uses flock(LOCK_EX|LOCK_NB), not Dart's
/// process-scoped fcntl locks. Two independently opened file descriptors
/// contend even inside the same process (including different Dart isolates).
///
/// Keep the .lease file in place forever. Removing and recreating it would
/// allow two writers to lock separate inodes under the same name.
pub struct RsProFileLease {
    file: Mutex<Option<File>>,
}

impl RsProFileLease {
    /// Explicitly release the lease after all receive writes/hashes finish.
    /// Dropping this Rust object also closes the file and releases the lock.
    #[frb(sync)]
    pub fn release(&self) {
        if let Ok(mut handle) = self.file.lock() {
            handle.take();
        }
    }
}

/// Caller must pass an app-private, canonical lease pathname derived from
/// session+file identity, not an attacker-controlled path from a network peer.
/// This operation never deletes the lease file and never waits indefinitely.
#[frb(sync)]
pub fn acquire_pro_file_lease(path: String) -> Result<RsProFileLease, String> {
    #[cfg(unix)]
    {
        use std::fs::OpenOptions;
        use std::os::fd::AsRawFd;
        use std::os::unix::fs::OpenOptionsExt;

        let file = OpenOptions::new()
            .read(true)
            .write(true)
            .create(true)
            .mode(0o600)
            .custom_flags(libc::O_NOFOLLOW)
            .open(path)
            .map_err(|_| "Cannot open Pro private lease file".to_string())?;

        // SAFETY: as_raw_fd() belongs to the live File object; flock only
        // accesses this fd and does not dereference any caller pointer.
        let status = unsafe { libc::flock(file.as_raw_fd(), libc::LOCK_EX | libc::LOCK_NB) };
        if status != 0 {
            return Err("Pro partial file already has another writer (or cannot be locked)".to_string());
        }
        Ok(RsProFileLease {
            file: Mutex::new(Some(file)),
        })
    }
    #[cfg(not(unix))]
    {
        let _ = path;
        Err("Native Pro writer leases are not available on this platform".to_string())
    }
}

#[cfg(all(test, unix))]
mod tests {
    use super::*;

    #[test]
    fn independent_handles_compete_and_release_without_deleting_lease_file() {
        let path = std::env::temp_dir()
            .join(format!("pro-writer-{}.lease", uuid::Uuid::new_v4()))
            .to_string_lossy()
            .to_string();
        let first = acquire_pro_file_lease(path.clone()).expect("first lease");
        assert!(acquire_pro_file_lease(path.clone()).is_err());
        assert!(std::path::Path::new(&path).exists());
        first.release();

        let second = acquire_pro_file_lease(path.clone()).expect("second lease");
        assert!(acquire_pro_file_lease(path.clone()).is_err());
        drop(second); // Simulates native object disposal after Dart GC.
        let third = acquire_pro_file_lease(path.clone()).expect("lease after disposal");
        third.release();

        // Tests may remove their private one-off lockfile; production code
        // NEVER unlinks a lease file because that can break inode locking.
        std::fs::remove_file(path).unwrap();
    }

    #[test]
    fn a_second_thread_in_the_same_process_must_not_acquire_the_writer_lease() {
        let path = std::env::temp_dir()
            .join(format!("pro-writer-thread-{}.lease", uuid::Uuid::new_v4()))
            .to_string_lossy()
            .to_string();
        let first = acquire_pro_file_lease(path.clone()).unwrap();
        let contender_path = path.clone();
        let result = std::thread::spawn(move || acquire_pro_file_lease(contender_path).is_err())
            .join()
            .unwrap();
        assert!(result, "a separate isolate/thread must not become a writer");
        first.release();
        assert!(acquire_pro_file_lease(path.clone()).is_ok());
        std::fs::remove_file(path).unwrap();
    }
}
