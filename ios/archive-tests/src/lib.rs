include!("../../../src/OpenGMK/gm8emulator/src/ios/archive.rs");
#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Write;
    fn temp()->PathBuf {static N:std::sync::atomic::AtomicU64=std::sync::atomic::AtomicU64::new(0);let p=std::env::temp_dir().join(format!("reload-ios-{}-{}",std::process::id(),N.fetch_add(1,std::sync::atomic::Ordering::Relaxed)));fs::create_dir_all(&p).unwrap();p}
    fn zip_at(dir:&Path,entries:&[(&str,&[u8])])->PathBuf {let path=dir.join("input.zip");let mut z=zip::ZipWriter::new(fs::File::create(&path).unwrap());for (name,data)in entries{z.start_file(*name,zip::write::SimpleFileOptions::default()).unwrap();z.write_all(data).unwrap();}z.finish().unwrap();path}
    #[test]fn imports_nested_game(){let d=temp();let z=zip_at(&d,&[("release/Reloaded.exe",b"MZ"),("release/data/test.txt",b"ok")]);let out=d.join("game");extract(&z,&out).unwrap();assert_eq!(find_exe(&out).unwrap(),out.join("release/Reloaded.exe"));fs::remove_dir_all(d).unwrap();}
    #[test]fn rejects_traversal_and_cleans_staging(){let d=temp();let z=zip_at(&d,&[("../escape",b"bad")]);let out=d.join("game");assert!(extract(&z,&out).is_err());assert!(!d.join("escape").exists());assert!(!out.with_extension("importing").exists());fs::remove_dir_all(d).unwrap();}
    #[test]fn preserves_existing_save(){let d=temp();let out=d.join("game");fs::create_dir(&out).unwrap();fs::write(out.join("save.sav"),b"original").unwrap();let z=zip_at(&d,&[("Reloaded.exe",b"MZ"),("data/test",b"x")]);assert!(extract(&z,&out).is_err());assert_eq!(fs::read(out.join("save.sav")).unwrap(),b"original");fs::remove_dir_all(d).unwrap();}
    #[test]fn rejects_non_game_without_installing(){let d=temp();let z=zip_at(&d,&[("note.txt",b"none")]);let out=d.join("game");assert!(extract(&z,&out).is_err());assert!(!out.exists());fs::remove_dir_all(d).unwrap();}
    #[test]fn rejects_windows_traversal(){let d=temp();let z=zip_at(&d,&[("..\\escape",b"bad")]);assert!(extract(&z,&d.join("game")).is_err());assert!(!d.join("escape").exists());fs::remove_dir_all(d).unwrap();}
}
