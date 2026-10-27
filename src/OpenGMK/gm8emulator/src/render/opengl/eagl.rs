//! EAGL presentation owned by the UIKit host. No GL context or UIKit object crosses an
//! FFI ownership boundary: the host retains the view until `gm_ios_run` returns.
use std::ffi::{c_char, c_void, CString};
use ramen::{connection::Connection, window::Window};
extern "C" {
    fn gm_ios_gl_create(view: *mut c_void) -> i32;
    fn gm_ios_gl_destroy();
    fn gm_ios_gl_present();
    fn gm_ios_gl_framebuffer() -> u32;
    fn gm_ios_gl_proc(name: *const c_char) -> *const c_void;
}
pub fn framebuffer() -> u32 { unsafe { gm_ios_gl_framebuffer() } }
pub struct PlatformImpl;
impl PlatformImpl {
    pub unsafe fn new(_: &Connection, window: &Window) -> Result<Self, String> {
        let _guard = crate::ios_main::gl_guard();
        if gm_ios_gl_create(window.xid()) != 0 { return Err("No se pudo crear OpenGL ES 3 en iOS".into()); }
        Ok(Self)
    }
    pub unsafe fn get_function_loader() -> Result<Box<dyn FnMut(&'static str) -> *const c_void>, String> {
        // Missing desktop-only calls deliberately stay null. gl_generator reports unsupported
        // operations instead of casting a no-op to an incompatible function signature.
        Ok(Box::new(|name| gm_ios_gl_proc(CString::new(name).unwrap().as_ptr())))
    }
    pub unsafe fn clean_function_loader() {}
    pub unsafe fn swap_buffers(&self) {
        let _guard = crate::ios_main::gl_guard();
        gm_ios_gl_present();
    }
    pub unsafe fn set_swap_interval(&self, _: u32) -> bool { true }
    pub unsafe fn get_swap_interval(&self) -> u32 { 1 }
    pub unsafe fn wait_vsync(&self) {}
}
impl Drop for PlatformImpl {
    fn drop(&mut self) {
        let _guard = crate::ios_main::gl_guard();
        unsafe { gm_ios_gl_destroy(); }
    }
}
