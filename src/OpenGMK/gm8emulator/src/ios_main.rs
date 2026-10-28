//! C ABI for the iOS launcher. This module has no dependency on JNI or Android.
use std::{ffi::{CStr, c_char, c_void}, sync::{Mutex, MutexGuard, Condvar, atomic::{AtomicBool, Ordering}}, path::{Path, PathBuf}};
use ramen::{input::Key, platform::ios::{self as platform, InputEvent}};
mod archive { include!("ios/archive.rs"); }
static ACTIVE: AtomicBool = AtomicBool::new(true);
static RUNNING: AtomicBool = AtomicBool::new(false);
static GL_LOCK: Mutex<()> = Mutex::new(());
static WAKE: Condvar = Condvar::new();
static LAST_ERROR: Mutex<String> = Mutex::new(String::new());
extern "C" { fn gm_ios_gl_finish(); }
pub fn gl_guard() -> MutexGuard<'static, ()> {
    let mut guard = GL_LOCK.lock().unwrap_or_else(|e| e.into_inner());
    while !ACTIVE.load(Ordering::Acquire) { guard = WAKE.wait(guard).unwrap_or_else(|e| e.into_inner()); }
    guard
}
pub fn wait_active() -> bool {
    let was_paused = !ACTIVE.load(Ordering::Acquire);
    drop(gl_guard());
    was_paused
}
#[no_mangle]
pub extern "C" fn gm_ios_set_active(active: bool) {
    {
        let _guard = GL_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        if !active { unsafe { gm_ios_gl_finish(); } }
        ACTIVE.store(active, Ordering::Release);
    }
    if active { WAKE.notify_all(); }
    crate::game::audio::set_output_paused(!active);
}
fn error(message: impl ToString) -> i32 {
    let message = message.to_string(); eprintln!("[ios] {message}");
    *LAST_ERROR.lock().unwrap_or_else(|e| e.into_inner()) = message; -1
}
#[no_mangle]
pub unsafe extern "C" fn gm_ios_error(out: *mut c_char, size: usize) {
    if out.is_null() || size == 0 { return; }
    let s = LAST_ERROR.lock().unwrap_or_else(|e| e.into_inner());
    let n = s.len().min(size-1); std::ptr::copy_nonoverlapping(s.as_ptr(), out.cast(), n); *out.add(n) = 0;
}
unsafe fn path(ptr: *const c_char) -> Result<PathBuf, String> {
    if ptr.is_null() { return Err("Ruta vacía".into()); }
    Ok(PathBuf::from(CStr::from_ptr(ptr).to_str().map_err(|e| e.to_string())?))
}
#[no_mangle]
pub unsafe extern "C" fn gm_ios_import(zip: *const c_char, destination: *const c_char) -> i32 {
    match std::panic::catch_unwind(|| -> Result<(), String> { archive::extract(&path(zip)?, &path(destination)?) }) {
        Ok(Ok(())) => 0, Ok(Err(e)) => error(e), Err(_) => error("Error inesperado al importar el ZIP"),
    }
}
#[no_mangle]
pub unsafe extern "C" fn gm_ios_has_game(root: *const c_char) -> bool {
    path(root).ok().and_then(|p| archive::find_exe(&p).ok()).is_some()
}
fn key(code: u32) -> Option<Key> {
    use Key::*;
    Some(match code {
        8=>Backspace,9=>Tab,13=>Return,16=>LeftShift,17=>LeftControl,18=>LeftAlt,27=>Escape,32=>Space,
        33=>PageUp,34=>PageDown,35=>End,36=>Home,37=>LeftArrow,38=>UpArrow,39=>RightArrow,40=>DownArrow,
        48=>Alpha0,49=>Alpha1,50=>Alpha2,51=>Alpha3,52=>Alpha4,53=>Alpha5,54=>Alpha6,55=>Alpha7,56=>Alpha8,57=>Alpha9,
        65=>A,66=>B,67=>C,68=>D,69=>E,70=>F,71=>G,72=>H,73=>I,74=>J,75=>K,76=>L,77=>M,
        78=>N,79=>O,80=>P,81=>Q,82=>R,83=>S,84=>T,85=>U,86=>V,87=>W,88=>X,89=>Y,90=>Z,
        112=>F1,113=>F2,114=>F3,115=>F4,116=>F5,117=>F6,118=>F7,119=>F8, _=>return None,
    })
}
#[no_mangle]
pub extern "C" fn gm_ios_key(code: u32, down: bool) {
    if let Some(key) = key(code) { platform::push_input(if down { InputEvent::KeyDown{key,text:None} } else { InputEvent::KeyUp{key} }); }
}
#[no_mangle]
pub extern "C" fn gm_ios_text(ch: u32) {
    if let Some(c) = char::from_u32(ch) {
        platform::push_input(InputEvent::Text(c));
    }
}
#[no_mangle]
pub extern "C" fn gm_ios_pointer(kind: u32, x: f32, y: f32, right: bool) {
    let button = if right {2} else {0};
    platform::push_input(match kind { 1=>InputEvent::PointerDown{x,y,button},2=>InputEvent::PointerUp{x,y,button},_=>InputEvent::PointerMoved{x,y} });
}
#[no_mangle]
pub extern "C" fn gm_ios_release_all() {
    for code in 0..128 { gm_ios_key(code, false); }
    platform::push_input(InputEvent::PointerUp{x:0.,y:0.,button:0});
    platform::push_input(InputEvent::PointerUp{x:0.,y:0.,button:2});
}
#[no_mangle]
pub unsafe extern "C" fn gm_ios_resize(w: u16, h: u16) { platform::push_resize(w,h); }
#[no_mangle]
pub extern "C" fn gm_ios_close() { platform::push_input(InputEvent::CloseRequest); }
#[no_mangle]
pub unsafe extern "C" fn gm_ios_run(view: *mut c_void, w: u32, h: u32, root: *const c_char, font: *const c_char, smoke: bool) -> i32 {
    if RUNNING.swap(true, Ordering::AcqRel) { return error("Ya hay una sesión en curso"); }
    let result=std::panic::catch_unwind(|| -> Result<i32,String> {
        platform::drain_pending_input(); platform::set_native_window(view,w,h);
        if smoke { return smoke_test(w,h); }
        let root=path(root)?; let exe=archive::find_exe(&root)?;
        std::env::set_current_dir(exe.parent().ok_or("Carpeta del juego inválida")?).map_err(|e|e.to_string())?;
        if let Ok(sf)=path(font) { std::env::set_var("OPENGMK_SOUNDFONT",sf); }
        std::env::set_var("OPENGMK_SCALING","aspect");
        std::env::set_var("OPENGMK_RENDER","native");
        Ok(crate::run_game(vec!["gm8emulator".into(),exe.to_string_lossy().into_owned()]))
    });
    crate::game::audio::ios::stop();
    platform::set_native_window(std::ptr::null_mut(),0,0); RUNNING.store(false,Ordering::Release);
    match result { Ok(Ok(0))=>0, Ok(Ok(n))=>error(format!("El motor terminó con código {n}. Revisá emulator.log")), Ok(Err(e))=>error(e), Err(_)=>error("El motor se detuvo. Revisá emulator.log") }
}
fn smoke_test(w:u32,h:u32)->Result<i32,String> {
    use crate::render::{Renderer,RendererOptions,Scaling};
    let connection=ramen::connection::Connection::new().map_err(|e|format!("{e:?}"))?;
    let window=connection.builder().size((320,240)).build().map_err(|e|format!("{e:?}"))?;
    let mut renderer=Renderer::new((),&connection,&RendererOptions{size:(320,240),..Default::default()},&window,(0.0,0.0,0.0).into())?;
    renderer.push_atlases(crate::render::atlas::AtlasBuilder::new(renderer.max_texture_size() as i32))?;
    renderer.set_view(0,0,320,240,0.0,0,0,320,240);
    renderer.clear_view((0.1,0.25,0.6).into(),1.0);
    renderer.draw_rectangle(80.,60.,240.,180.,0x00ff00,1.0);
    renderer.present(w,h,Scaling::Aspect(-1.0));
    let px=renderer.get_pixels(160,120,1,1);
    if px.len()<4 || px[1]<200 || px[0]>30 || px[2]>30 {return Err(format!("Render test: píxel inesperado {px:?}"));}
    platform::drain_pending_input(); // Discard initial drawable resize events.
    gm_ios_key(90,true);gm_ios_key(90,false);gm_ios_text('ñ' as u32);
    let events=platform::drain_pending_input();
    if !matches!(events.as_slice(), [InputEvent::KeyDown{key:Key::Z,text:None},InputEvent::KeyUp{key:Key::Z},InputEvent::Text('ñ')]) {
        return Err(format!("Falló la cola de controles: {events:?}"));
    }
    crate::game::audio::ios::smoke_test()?;
    eprintln!("IOS_SMOKE_OK: shader, framebuffer, readback, input and RemoteIO PCM callback");
    std::thread::sleep(std::time::Duration::from_secs(8));
    Ok(0)
}
