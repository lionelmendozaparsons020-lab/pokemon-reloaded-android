//! PCM output into the host's RemoteIO AudioUnit. The existing WAV/MP3/MIDI mixer is reused.
use std::sync::{Mutex, Arc, atomic::{AtomicU32, AtomicI32, AtomicBool, Ordering}};
use udon::source::{ChannelCount, SampleRate, Source};
use super::mixer::{Mixer, MixerHandle};
static MIXER: Mutex<Option<Mixer>> = Mutex::new(None);
static PAUSED: AtomicBool = AtomicBool::new(false);
static START_STATUS: AtomicI32 = AtomicI32::new(0);
static CHECK_OUTPUT: AtomicBool = AtomicBool::new(false);
static HEARD_SAMPLES: AtomicBool = AtomicBool::new(false);
extern "C" { fn gm_ios_audio_start() -> i32; fn gm_ios_audio_pause(paused: bool); fn gm_ios_audio_stop(); }
pub fn open(volume: Arc<AtomicU32>) -> (ChannelCount, SampleRate, MixerHandle) {
    let channels = ChannelCount::new(2).unwrap();
    let rate = SampleRate::new(48000).unwrap();
    let (mixer, handle) = Mixer::new(rate, channels, volume);
    *MIXER.lock().unwrap_or_else(|e| e.into_inner()) = Some(mixer);
    let status = unsafe { gm_ios_audio_start() };
    START_STATUS.store(status, Ordering::Release);
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
    CHECK_OUTPUT.store(false, Ordering::Release);
}
/// Verify that RemoteIO actually requests and receives nonzero samples through the mixer.
/// This tests the software output path, not the physical speaker or the game's audio assets.
pub fn smoke_test() -> Result<(), String> {
    PAUSED.store(false, Ordering::Release);
    HEARD_SAMPLES.store(false, Ordering::Release);
    CHECK_OUTPUT.store(true, Ordering::Release);
    let (channels, rate, handle) = open(Arc::new(AtomicU32::new(1.0f32.to_bits())));
    let status = START_STATUS.load(Ordering::Acquire);
    if status != 0 { stop(); return Err(format!("RemoteIO no inició: {status}")); }
    let samples: Vec<f32> = (0..96_000).map(|i| {
        ((i / 2) as f32 * 440.0 * std::f32::consts::TAU / 48_000.0).sin() * 0.03
    }).collect();
    handle.add_exclusive(udon::Player::new(channels, rate, samples.into_boxed_slice()), -1)
        .map_err(|e| format!("Mixer: {e:?}"))?;
    for _ in 0..100 {
        if HEARD_SAMPLES.load(Ordering::Acquire) { stop(); return Ok(()); }
        std::thread::sleep(std::time::Duration::from_millis(20));
    }
    stop();
    Err("RemoteIO no solicitó muestras de audio".into())
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
            if CHECK_OUTPUT.load(Ordering::Relaxed) && data.iter().any(|s| s.abs() > 0.001) {
                HEARD_SAMPLES.store(true, Ordering::Release);
            }
        }
    }
}
