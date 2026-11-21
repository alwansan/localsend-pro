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
    directory: std::path::PathBuf,
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

    /// Complete a checkpoint commit after the Dart side has flushed the
    /// .part and .pending files and atomically renamed .pending to .json.
    /// On Linux/Android, fsync on the PARENT DIRECTORY is required to
    /// persist the directory entry after abrupt power loss. If this fails,
    /// the caller must NOT acknowledge the chunk and must reopen/replay.
    ///
    /// This intentionally uses the directory captured from the locked
    /// .lease path, not any user-controlled path supplied in a later call.
    #[frb(sync)]
    pub fn sync_checkpoint_directory(&self) -> Result<(), String> {
        let guard = self
            .file
            .lock()
            .map_err(|_| "Pro writer lease is poisoned".to_string())?;
        if guard.is_none() {
            return Err("Pro writer lease has already been released".to_string());
        }

        #[cfg(unix)]
        {
            use std::os::unix::fs::OpenOptionsExt;
            let directory = std::fs::OpenOptions::new()
                .read(true)
                .custom_flags(libc::O_DIRECTORY | libc::O_NOFOLLOW | libc::O_CLOEXEC)
                .open(&self.directory)
                .map_err(|_| "Cannot open app-private Pro checkpoint directory".to_string())?;
            directory
                .sync_all()
                .map_err(|_| "Could not sync Pro checkpoint directory".to_string())?;
            Ok(())
        }
        #[cfg(not(unix))]
        {
            Err("Pro checkpoint directory sync unsupported on this platform".to_string())
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

        let directory = std::path::Path::new(&path)
            .parent()
            .ok_or_else(|| "Invalid Pro lease file path".to_string())?
            .to_path_buf();
        let file = OpenOptions::new()
            .read(true)
            .write(true)
            .create(true)
            .mode(0o600)
            .custom_flags(libc::O_NOFOLLOW)
            .open(&path)
            .map_err(|_| "Cannot open Pro private lease file".to_string())?;

        // SAFETY: as_raw_fd() belongs to the live File object; flock only
        // accesses this fd and does not dereference any caller pointer.
        let status = unsafe { libc::flock(file.as_raw_fd(), libc::LOCK_EX | libc::LOCK_NB) };
        if status != 0 {
            return Err("Pro partial file already has another writer (or cannot be locked)".to_string());
        }
        Ok(RsProFileLease {
            file: Mutex::new(Some(file)),
            directory,
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
    fn checkpoint_directory_sync_requires_active_writer_and_survives_rename() {
        use std::io::Write;
        let dir = std::env::temp_dir().join(format!("pro-fsync-{}", uuid::Uuid::new_v4()));
        std::fs::create_dir(&dir).unwrap();
        let lease_path = dir.join("file.lease");
        let lease = acquire_pro_file_lease(lease_path.to_string_lossy().to_string()).unwrap();
        let part = dir.join("file.part");
        let mut data = std::fs::File::create(&part).unwrap();
        data.write_all(b"known-verified-bytes").unwrap();
        data.sync_all().unwrap();

        let pending = dir.join("file.pending");
        let mut manifest = std::fs::File::create(&pending).unwrap();
        manifest.write_all(br#"{"confirmedOffset":20}"#).unwrap();
        manifest.sync_all().unwrap();
        std::fs::rename(&pending, dir.join("file.checkpoint.json")).unwrap();

        lease.sync_checkpoint_directory().unwrap();
        assert!(dir.join("file.checkpoint.json").exists());
        lease.release();
        assert!(lease.sync_checkpoint_directory().is_err());
        drop(data);
        drop(manifest);
        std::fs::remove_dir_all(dir).unwrap();
    }

    #[test]
    fn symlinked_lease_file_is_not_accepted() {
        use std::os::unix::fs::symlink;
        let dir = std::env::temp_dir().join(format!("pro-symlink-{}", uuid::Uuid::new_v4()));
        std::fs::create_dir(&dir).unwrap();
        let target = dir.join("ordinary-file");
        std::fs::write(&target, b"untouched").unwrap();
        let link = dir.join("file.lease");
        symlink(&target, &link).unwrap();
        assert!(acquire_pro_file_lease(link.to_string_lossy().to_string()).is_err());
        assert_eq!(std::fs::read(target).unwrap(), b"untouched");
        std::fs::remove_dir_all(dir).unwrap();
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
