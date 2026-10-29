//! Save directory selector used by Pokémon Reloaded test mode.
//! Only the 3 game-save folders are routed; all installed resources stay shared.
use std::{fs, path::{Path, PathBuf}, sync::{Once, atomic::{AtomicBool, Ordering}}};
use std::os::unix::fs::symlink;

fn copy_tree(source: &Path, target: &Path) -> Result<(), String> {
    fs::create_dir_all(target).map_err(|e| e.to_string())?;
    if !source.exists() { return Ok(()); }
    for e in fs::read_dir(source).map_err(|e| e.to_string())? {
        let e = e.map_err(|e| e.to_string())?;
        let kind = e.file_type().map_err(|e| e.to_string())?;
        let dest = target.join(e.file_name());
        if kind.is_dir() {
            copy_tree(&e.path(), &dest)?;
        } else if kind.is_file() {
            fs::copy(e.path(), dest).map_err(|e| e.to_string())?;
        } else {
            return Err("save contains an unsupported link".into());
        }
    }
    Ok(())
}

fn select_save_dirs(enabled: bool) -> Result<(), String> {
    let storage = crate::android_main::storage_dir();
    let base = storage.join("game").join("data");
    if !base.is_dir() { return Err("game assets not installed".into()); }
    let modes = storage.join("save_modes");
    let normal = modes.join("normal");
    let mods = modes.join("mods");
    fs::create_dir_all(&normal).map_err(|e| e.to_string())?;
    fs::create_dir_all(&mods).map_err(|e| e.to_string())?;

    for category in ["partidas", "equipos", "char_custom"] {
        let active = base.join(category);
        let original = normal.join(category);
        let experimental = mods.join(category);

        if let Ok(meta) = fs::symlink_metadata(&active) {
            if meta.file_type().is_symlink() {
                let target = fs::read_link(&active).map_err(|e| e.to_string())?;
                if target != original && target != experimental {
                    return Err(format!("unexpected save link: {}", active.display()));
                }
            } else if meta.is_dir() {
                if !original.exists() {
                    fs::rename(&active, &original).map_err(|e| e.to_string())?;
                } else {
                    // Preserve imported files rather than overwriting existing saves.
                    let recovered = modes.join(format!("imported_{}", category));
                    if recovered.exists() {
                        return Err(format!("imported save needs manual review: {}", active.display()));
                    }
                    fs::rename(&active, recovered).map_err(|e| e.to_string())?;
                }
            } else {
                return Err(format!("unexpected save path: {}", active.display()));
            }
        }

        fs::create_dir_all(&original).map_err(|e| e.to_string())?;

        if !experimental.exists() {
            let partial = mods.join(format!("{}.copying", category));
            if partial.exists() {
                fs::remove_dir_all(&partial).map_err(|e| e.to_string())?;
            }
            copy_tree(&original, &partial)?;
            fs::rename(&partial, &experimental).map_err(|e| e.to_string())?;
        } else if fs::symlink_metadata(&experimental)
            .map(|m| !m.is_dir() || m.file_type().is_symlink()).unwrap_or(true)
        {
            return Err(format!("invalid experimental save directory: {}", experimental.display()));
        }

        let selected = if enabled { &experimental } else { &original };
        let pending = base.join(format!(".{}.mode_new", category));
        if fs::symlink_metadata(&pending).is_ok() {
            fs::remove_file(&pending).map_err(|e| e.to_string())?;
        }
        symlink(selected, &pending).map_err(|e| e.to_string())?;
        fs::rename(&pending, &active).map_err(|e| e.to_string())?;
    }
    eprintln!("[mods] active save profile: {}", if enabled {"mods"} else {"normal"});
    Ok(())
}

pub(super) fn initialize_once(flag: &AtomicBool) {
    static INITIALIZED: Once = Once::new();
    INITIALIZED.call_once(|| {
        let config = fs::read_to_string(crate::android_main::storage_path("mods.conf"))
            .unwrap_or_default();
        let enabled = config.lines().any(|l| l.trim() == "mod_mode=1");
        if let Err(error) = select_save_dirs(enabled) {
            panic!("could not safely prepare save mode: {}", error);
        }
        flag.store(enabled, Ordering::Relaxed);
    });
}
