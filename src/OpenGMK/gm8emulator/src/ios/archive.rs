use std::{fs, io::{self, Read}, path::{Path, PathBuf, Component}};
const MAX_BYTES: u64 = 12 * 1024 * 1024 * 1024;
const MAX_FILES: usize = 150_000;
/// New imports never overwrite an existing game or its saves.
pub fn extract(archive_path: &Path, destination: &Path) -> Result<(), String> {
    if destination.exists() { return Err("La carpeta de destino ya existe; se conservaron sus partidas".into()); }
    let mut archive = zip::ZipArchive::new(fs::File::open(archive_path).map_err(|e|e.to_string())?).map_err(|e|e.to_string())?;
    if archive.len() > MAX_FILES { return Err("El ZIP contiene demasiados archivos".into()); }
    let staging=destination.with_extension("importing");
    fs::create_dir(&staging).map_err(|e|e.to_string())?;
    let result=(|| -> Result<(),String> {
        let mut total=0u64;
        for i in 0..archive.len() {
            let mut entry=archive.by_index(i).map_err(|e|e.to_string())?;
            let name=entry.name().replace('\\',"/");
            if name.contains(':') || Path::new(&name).components().any(|c| !matches!(c,Component::Normal(_)|Component::CurDir)) {
                return Err(format!("Ruta no válida dentro del ZIP: {name}"));
            }
            if entry.unix_mode().map(|m|m & 0o170000 == 0o120000).unwrap_or(false) { return Err("El ZIP contiene enlaces simbólicos".into()); }
            let output=staging.join(&name);
            if entry.is_dir() { fs::create_dir_all(&output).map_err(|e|e.to_string())?; continue; }
            total=total.checked_add(entry.size()).filter(|n|*n<=MAX_BYTES).ok_or("El ZIP supera el límite de 12 GB")?;
            if let Some(parent)=output.parent() { fs::create_dir_all(parent).map_err(|e|e.to_string())?; }
            let mut file=fs::OpenOptions::new().write(true).create_new(true).open(&output).map_err(|e|e.to_string())?;
            let expected=entry.size();
            let copied=io::copy(&mut (&mut entry).take(expected+1),&mut file).map_err(|e|e.to_string())?;
            if copied!=expected { return Err(format!("Archivo incompleto: {name}")); }
        }
        let exe=find_exe(&staging)?;
        if !exe.parent().unwrap().join("data").is_dir() { return Err("Falta la carpeta data junto al ejecutable del juego".into()); }
        fs::rename(&staging,destination).map_err(|e|e.to_string())?;
        Ok(())
    })();
    if result.is_err() { let _=fs::remove_dir_all(&staging); }
    result
}
pub fn find_exe(root:&Path)->Result<PathBuf,String> {
    fn walk(dir:&Path,depth:usize,out:&mut Vec<PathBuf>)->io::Result<()> {
        if depth>10 {return Ok(());}
        for entry in fs::read_dir(dir)? {
            let entry=entry?;let kind=entry.file_type()?;let p=entry.path();
            if kind.is_symlink() {continue;}
            if kind.is_dir() && !dir.join("data").is_dir() {walk(&p,depth+1,out)?;}
            else if p.extension().and_then(|s|s.to_str()).is_some_and(|s|s.eq_ignore_ascii_case("exe")) && dir.join("data").is_dir() {out.push(p);}
        }
        Ok(())
    }
    let mut found=Vec::new();walk(root,0,&mut found).map_err(|e|e.to_string())?;
    found.sort();
    if let Some(p)=found.iter().find(|p|p.file_name().unwrap().to_string_lossy().to_lowercase().contains("reload")){return Ok(p.clone());}
    if found.len()==1 {return Ok(found.remove(0));}
    Err("No se encontró un ejecutable de Reloaded con su carpeta data".into())
}
