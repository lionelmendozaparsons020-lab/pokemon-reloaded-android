use std::{collections::BTreeSet, fs, io::{self, Read, Write}, path::{Component, Path, PathBuf}};
const FOLDERS: [&str; 3] = ["partidas", "equipos", "char_custom"];
const LIMIT: u64 = 1024 * 1024 * 1024;
fn err(e: impl ToString) -> String { e.to_string() }
fn slot_suffix(name: &str) -> Option<(u32, &str)> {
    let rest = name.strip_prefix("reloaded")?;
    let n = rest.bytes().take_while(u8::is_ascii_digit).count();
    if n == 0 || !matches!(rest.as_bytes().get(n), Some(b'.' | b'_')) { return None; }
    Some((rest[..n].parse().ok()?, &rest[n..]))
}
fn collect(root: &Path, at: &Path, out: &mut Vec<PathBuf>) -> Result<(), String> {
    if !at.exists() { return Ok(()); }
    if fs::symlink_metadata(at).map_err(err)?.file_type().is_symlink() { return Err("No se admiten enlaces en las partidas".into()); }
    for item in fs::read_dir(at).map_err(err)? {
        let p = item.map_err(err)?.path();
        let t = fs::symlink_metadata(&p).map_err(err)?.file_type();
        if t.is_symlink() { return Err("No se admiten enlaces en las partidas".into()); }
        if t.is_dir() { collect(root, &p, out)?; } else if t.is_file() { out.push(p.strip_prefix(root).map_err(err)?.to_path_buf()); }
    }
    Ok(())
}
fn copy_tree(from: &Path, to: &Path) -> Result<(), String> {
    fs::create_dir_all(to).map_err(err)?;
    let mut files = Vec::new(); collect(from, from, &mut files)?;
    for rel in files { let dst = to.join(&rel); fs::create_dir_all(dst.parent().unwrap()).map_err(err)?; fs::copy(from.join(rel), dst).map_err(err)?; }
    Ok(())
}
// A journal permits rollback if iOS suspends/terminates the app between directory renames.
pub fn recover(data: &Path) -> Result<(), String> {
    let journal = data.join(".save-import");
    if !journal.exists() { return Ok(()); }
    if journal.join("started").exists() && !journal.join("committed").exists() {
        for folder in FOLDERS {
            let dest = data.join(folder); let old = journal.join(format!("old-{folder}"));
            if old.exists() { if dest.exists() { fs::remove_dir_all(&dest).map_err(err)?; } fs::rename(old, &dest).map_err(err)?; }
            else if journal.join(format!("new-{folder}")).exists() && dest.exists() { fs::remove_dir_all(dest).map_err(err)?; }
        }
    }
    fs::remove_dir_all(journal).map_err(err)
}
pub fn export(data: &Path, output: &Path, slot: u32) -> Result<(), String> {
    recover(data)?;
    let mut files = Vec::new();
    for folder in FOLDERS { if slot == 0 || folder == "partidas" { collect(data, &data.join(folder), &mut files)?; } }
    files.retain(|p| slot == 0 || p.file_name().and_then(|s| s.to_str()).and_then(slot_suffix).is_some_and(|(n,_)| n == slot));
    if files.is_empty() { return Err("No hay partidas que exportar todavía".into()); }
    files.sort(); let temp = output.with_extension("partial");
    let f = fs::OpenOptions::new().write(true).create_new(true).open(&temp).map_err(err)?;
    let result = (|| {
        let mut zip = zip::ZipWriter::new(f); let mut total = 0u64;
        for rel in files {
            let mut input = fs::File::open(data.join(&rel)).map_err(err)?;
            total = total.checked_add(input.metadata().map_err(err)?.len()).filter(|n| *n <= LIMIT).ok_or("Las partidas superan 1 GB")?;
            zip.start_file(rel.to_string_lossy().replace('\\', "/"), zip::write::SimpleFileOptions::default().compression_method(zip::CompressionMethod::Deflated)).map_err(err)?;
            io::copy(&mut input, &mut zip).map_err(err)?;
        }
        zip.finish().map_err(err)?.sync_all().map_err(err)?;
        fs::rename(&temp, output).map_err(err)
    })();
    if result.is_err() { let _ = fs::remove_file(temp); } result
}
pub fn import(data: &Path, input: &Path, slot: u32) -> Result<usize, String> {
    if !data.is_dir() { return Err("Primero importa el juego".into()); }
    if slot > 3 { return Err("Número de partida inválido".into()); }
    recover(data)?;
    let mut zip = zip::ZipArchive::new(fs::File::open(input).map_err(err)?).map_err(err)?;
    if zip.len() > 20000 { return Err("Demasiados archivos en el ZIP de partidas".into()); }
    let journal = data.join(".save-import"); fs::create_dir(&journal).map_err(err)?;
    let result = (|| {
        let incoming = journal.join("incoming"); fs::create_dir(&incoming).map_err(err)?;
        let mut names = BTreeSet::new(); let mut sources = BTreeSet::new(); let mut total = 0u64;
        for i in 0..zip.len() {
            let mut e = zip.by_index(i).map_err(err)?; let raw = e.name().replace('\\', "/");
            if raw.contains(':') || Path::new(&raw).components().any(|c| !matches!(c, Component::Normal(_) | Component::CurDir)) || e.unix_mode().is_some_and(|m| m & 0o170000 == 0o120000) { return Err("El ZIP contiene una ruta no segura".into()); }
            if e.is_dir() { continue; }
            let name = raw.strip_prefix("data/").unwrap_or(&raw);
            if !FOLDERS.iter().any(|f| name.starts_with(&format!("{f}/"))) { continue; }
            let mut name = name.to_string();
            if slot > 0 {
                let Some(base) = name.strip_prefix("partidas/").filter(|n| !n.contains('/')) else { continue; };
                let Some((n, suffix)) = slot_suffix(base) else { continue; };
                sources.insert(n); if sources.len() > 1 { return Err("El ZIP contiene varias partidas; usa Importar todas o un ZIP de una sola partida".into()); }
                name = format!("partidas/reloaded{slot}{suffix}");
            }
            if !names.insert(name.clone()) { return Err("El ZIP contiene archivos repetidos".into()); }
            total = total.checked_add(e.size()).filter(|n| *n <= LIMIT).ok_or("Las partidas superan 1 GB")?;
            let target = incoming.join(&name); fs::create_dir_all(target.parent().unwrap()).map_err(err)?;
            let mut f = fs::File::create(&target).map_err(err)?; let expected = e.size();
            if io::copy(&mut (&mut e).take(expected + 1), &mut f).map_err(err)? != expected { return Err("Archivo de partida incompleto".into()); }
            f.flush().map_err(err)?;
        }
        if names.is_empty() { return Err("Ese ZIP no contiene partidas, equipos ni personajes de Reloaded".into()); }
        let touched: Vec<&str> = FOLDERS.into_iter().filter(|f| incoming.join(f).exists()).collect();
        for folder in &touched {
            let original = data.join(folder); let next = journal.join(format!("next-{folder}"));
            if original.exists() { copy_tree(&original, &next)?; } else { fs::create_dir(&next).map_err(err)?; fs::write(journal.join(format!("new-{folder}")), b"").map_err(err)?; }
            copy_tree(&incoming.join(folder), &next)?;
        }
        fs::write(journal.join("started"), b"").map_err(err)?;
        for folder in &touched {
            let original = data.join(folder);
            if original.exists() { fs::rename(&original, journal.join(format!("old-{folder}"))).map_err(err)?; }
            fs::rename(journal.join(format!("next-{folder}")), original).map_err(err)?;
        }
        fs::write(journal.join("committed"), b"").map_err(err)?;
        Ok(names.len())
    })();
    let cleanup = recover(data);
    match result { Ok(n) => { cleanup?; Ok(n) }, Err(e) => { cleanup?; Err(e) } }
}
