//! PCM output into the host's RemoteIO AudioUnit. The existing WAV/MP3/MIDI mixer is reused.
use std::sync::{Mutex, Arc, atomic::{AtomicU32, AtomicBool, Ordering}};
use udon::source::{ChannelCount, SampleRate, Source};
use super::mixer::{Mixer, MixerHandle};
static MIXER: Mutex<Option<Mixer>> = Mutex::new(None);
static PAUSED: AtomicBool = AtomicBool::new(false);
extern "C" { fn gm_ios_audio_start() -> i32; fn gm_ios_audio_pause(paused: bool); fn gm_ios_audio_stop(); }
pub fn open(volume: Arc<AtomicU32>) -> (ChannelCount, SampleRate, MixerHandle) {
    let channels = ChannelCount::new(2).unwrap();
    let rate = SampleRate::new(48000).unwrap();
    let (mixer, handle) = Mixer::new(rate, channels, volume);
    *MIXER.lock().unwrap_or_else(|e| e.into_inner()) = Some(mixer);
    let status = unsafe { gm_ios_audio_start() };
    if status != 0 { eprintln!("[ios audio] RemoteIO error: {status}"); }
    (channels, rate, handle)
}
pub fn set_paused(paused: bool) {
    PAUSED.store(paused, Ordering::Release);
    unsafe { gm_ios_audio_pause(paused); }
}
pub fn stop() {
    unsafe { gm_ios_audio_stop(); }
    *MIXER.lock().unwrap_or_else(|e| e.into_inner()) = None;
}
/// Host supplies `frames * 2` writable float samples, interleaved LR at 48 kHz.
#[no_mangle]
pub unsafe extern "C" fn gm_ios_audio_fill(out: *mut f32, frames: u32) {
    if out.is_null() || frames > 65536 { return; }
    let data = std::slice::from_raw_parts_mut(out, frames as usize * 2);
    data.fill(0.0);
    if PAUSED.load(Ordering::Acquire) { return; }
    // Never block the realtime callback behind the game thread.
    if let Ok(mut slot) = MIXER.try_lock() {
        if let Some(mixer) = slot.as_mut() {
            let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| mixer.write_samples(data)));
            if result.is_err() { data.fill(0.0); }
        }
    }
}
