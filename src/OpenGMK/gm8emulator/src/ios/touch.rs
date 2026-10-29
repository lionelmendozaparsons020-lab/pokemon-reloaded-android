// iOS event adapter for the Android 0.3.9/V22 touch dispatcher.
// Artwork, layout, hit testing, joystick hysteresis, wheels and gesture recognizers
// use the same engine modules on both platforms. Only OS events differ.
use std::{collections::HashMap, sync::Mutex, time::{Duration, Instant}};
use ramen::{input::Key, platform::ios as platform};
/// Which control each active pointer is currently holding, so a multi-touch release is paired with
/// the right control. Keyed by Android pointer id.
static POINTER_CONTROLS: Mutex<Option<HashMap<i32, usize>>> = Mutex::new(None);

/// The pointer the party wheel is following, if any.
static WHEEL_PTR: Mutex<Option<i32>> = Mutex::new(None);

/// Android key events may arrive between game frames; a tap must survive the next sample.
/// Repeated bag arrows require DOWN and UP in separate frames, not one held key forever.
enum TapPhase {
    Idle,
    Pressed { key: Key, started: Instant, frame: u64, navigation: bool },
    Released { since: Instant, frame: u64, navigation: bool },
}
struct TapSequence {
    phase: TapPhase,
    queued: std::collections::VecDeque<(Key, bool)>,
}
static TAPS: Mutex<TapSequence> = Mutex::new(TapSequence {
    phase: TapPhase::Idle, queued: std::collections::VecDeque::new(),
});
const TAP_HOLD: Duration = Duration::from_millis(55);
const TAP_GAP: Duration = Duration::from_millis(25);
const TAP_FRAME_FALLBACK: Duration = Duration::from_millis(170);

fn queue_tap(key: Key, navigation: bool) {
    if crate::touch_controls::key_held_by_buttons(key) || joystick_holds(key) { return }
    let mut taps = TAPS.lock().unwrap();
    if navigation {
        // Follow the newest direction; old swipes must not continue scrolling.
        if taps.queued.iter().any(|(queued,nav)| *nav && *queued!=key) {
            taps.queued.retain(|(_,nav)| !*nav);
        }
        // Navigation has a tiny bounded queue, unlike normal SEL/confirm taps.
        if taps.queued.iter().filter(|(_,nav)| *nav).count() >= 3 {
            if let Some(at)=taps.queued.iter().position(|(_,nav)| *nav) {
                taps.queued.remove(at);
            }
        }
    }
    if taps.queued.len() < 32 { taps.queued.push_back((key,navigation)); }
}
pub(super) fn tap_key(key: Key) { queue_tap(key,false); }
fn tap_navigation_key(key: Key) { queue_tap(key,true); }

/// On release, allow only one last pending step and discard old queued movement.
fn trim_navigation_taps() {
    let mut taps=TAPS.lock().unwrap();
    let mut left=0;
    taps.queued.retain(|(_,nav)| {
        if !*nav { true } else {
            left+=1;
            left<=1
        }
    });
}
fn flush_tapped_keys() {
    let mut taps = TAPS.lock().unwrap();
    let frame = crate::touch_navigation::frame();
    let phase = std::mem::replace(&mut taps.phase, TapPhase::Idle);
    taps.phase = match phase {
        TapPhase::Pressed { key, started, frame: first_frame, navigation } => {
            let elapsed = started.elapsed();
            let hold = if navigation { crate::touch_navigation::NAV_TAP_HOLD } else { TAP_HOLD };
            let fallback = if navigation { crate::touch_navigation::NAV_HOLD_FALLBACK } else { TAP_FRAME_FALLBACK };
            if elapsed >= hold && (frame != first_frame || elapsed >= fallback) {
                if !crate::touch_controls::key_held_by_buttons(key) && !joystick_holds(key) {
                    platform::push_input(ramen::platform::ios::InputEvent::KeyUp { key });
                }
                TapPhase::Released { since: Instant::now(), frame, navigation }
            } else { TapPhase::Pressed { key, started, frame: first_frame, navigation } }
        }
        TapPhase::Released { since, frame: release_frame, navigation } => {
            let gap=if navigation { crate::touch_navigation::NAV_TAP_GAP } else { TAP_GAP };
            let fallback=if navigation { crate::touch_navigation::NAV_GAP_FALLBACK } else { TAP_FRAME_FALLBACK };
            if since.elapsed() >= gap && (frame != release_frame || since.elapsed() >= fallback) {
                TapPhase::Idle
            } else { TapPhase::Released { since, frame: release_frame, navigation } }
        }
        TapPhase::Idle => TapPhase::Idle,
    };
    if matches!(taps.phase, TapPhase::Idle) {
        while let Some((key,navigation)) = taps.queued.pop_front() {
            if crate::touch_controls::key_held_by_buttons(key) || joystick_holds(key) { continue }
            platform::push_input(ramen::platform::ios::InputEvent::KeyDown { key, text: None });
            taps.phase = TapPhase::Pressed { key, started: Instant::now(), frame, navigation };
            break
        }
    }
}

fn joystick_holds(key: Key) -> bool {
    let state=MOVEMENT_STATE.load(std::sync::atomic::Ordering::Relaxed);
    MOVEMENT_KEYS.iter().enumerate().any(|(i,k)| *k==key && state & (1<<i)!=0)
}

fn control_key_down(index: usize) {
    use crate::touch_controls as tc;
    if tc::controls()[index].name == "o" && matches!(tc::current_context(),tc::WORLD|tc::BATTLE|tc::SAFARI) {crate::touch_navigation::arm_bag();}
    else {crate::touch_navigation::disarm_bag();}
    let keys=tc::control_keys(index);
    let held=keys.map(|key| key.is_some_and(|key| tc::key_held_by_buttons(key) || joystick_holds(key)));
    tc::set_pressed(index,true);
    for (i,key) in keys.into_iter().enumerate() {
        if let Some(key)=key.filter(|_| !held[i]) {
            match key {Key::LeftArrow=>tc::picker_step(-1),Key::RightArrow=>tc::picker_step(1),_=>{}}
            platform::push_input(ramen::platform::ios::InputEvent::KeyDown {key,text:None});
        }
    }
    if tc::controls()[index].name==tc::COMBO_BUTTON_NAME {tc::set_combo_used();}
}

fn control_key_up(index: usize) {
    use crate::touch_controls as tc;
    if !tc::is_pressed(index) {return}
    tc::set_pressed(index,false);
    for key in tc::control_keys(index).into_iter().flatten() {
        if !tc::key_held_by_buttons(key) && !joystick_holds(key) {
            platform::push_input(ramen::platform::ios::InputEvent::KeyUp {key});
        }
    }
}

/// Pointers whose press was swallowed to bring the on-screen controls back, so that their release
/// is ignored too instead of reaching the game as a stray mouse-up.
static SWALLOWED_INPUTS: Mutex<Option<std::collections::HashSet<i32>>> = Mutex::new(None);

/// A touch on an on-screen control presses the key that control maps to; any other touch is
/// forwarded to the game as a mouse, exactly as before.
fn touch_feedback() { if crate::touch_appearance::settings().haptics { super::haptic(); } }
fn ime_set(visible: bool) { super::keyboard(visible); }

// Only the PC box uses a long press; menus, text entry and info overlays keep their input.
static BOX_TOUCH: Mutex<crate::box_touch::BoxTouch> = Mutex::new(crate::box_touch::BoxTouch::new());

fn box_touch_active() -> bool {
    use crate::touch_controls as tc;
    tc::box_open() && tc::current_context() == tc::MENU
        && !tc::info_window_open() && !tc::text_entry_open()
        && !matches!(tc::modal_id(), 9673 | 9674 | 7778)
}

fn emit_box_events(events: Vec<crate::box_touch::Event>) {
    use crate::box_touch::{Event, Point};
    use ramen::platform::ios::InputEvent;
    for event in events {
        platform::push_input(match event {
            Event::Move(Point(x, y)) => InputEvent::PointerMoved { x, y },
            Event::Down(Point(x, y), button) => InputEvent::PointerDown { x, y, button },
            Event::Up(Point(x, y), button) => InputEvent::PointerUp { x, y, button },
        });
    }
}

pub(super) fn pointer_down(id: i32, x: f32, y: f32) {
    // A new gesture cannot inherit a swallowed Up from an Android cancellation.
    if let Some(ids)=SWALLOWED_INPUTS.lock().unwrap().as_mut(){ids.remove(&id);}
    let (w, h) = platform::window_size();
    let (wf, hf) = (w as f32, h as f32);
    // The first touch after using a pad only brings the controls back. It must not also land in the
    // game as a click, or reaching for the on-screen buttons would act on whatever is under them.
    if crate::touch_controls::pad_active() {
        crate::touch_controls::set_pad_active(false);
        SWALLOWED_INPUTS.lock().unwrap().get_or_insert_with(std::collections::HashSet::new).insert(id);
        return
    }
    if box_touch_active() {
        if BOX_TOUCH.lock().unwrap().begin(id, crate::box_touch::Point(x, y), hf, Instant::now(), crate::touch_controls::box_carrying()) {
            platform::push_input(ramen::platform::ios::InputEvent::PointerMoved { x, y });
        } else {
            SWALLOWED_INPUTS.lock().unwrap().get_or_insert_with(std::collections::HashSet::new).insert(id);
        }
        return
    }
    let on_movement = wf > 0.0 && hf > 0.0 && crate::touch_controls::movement_hit(x / wf, y / hf, wf, hf);
    let hit = if wf > 0.0 && hf > 0.0 { crate::touch_controls::hit(x / wf, y / hf, wf, hf) } else { None };
    // SEL takes precedence over the joystick and any ordinary buttons behind its artwork.
    // Select on DOWN so canceled UPs and small finger drifts cannot drop a number press.
    if crate::field_controls::open() {
        if hit.is_some_and(|i| crate::touch_controls::controls()[i].name == crate::field_controls::NAME) {
            crate::field_controls::close();
        } else if let Some(slot) = crate::field_controls::item_at(x, y, wf, hf) {
            tap_key(crate::field_controls::KEYS[slot]);
            crate::field_controls::close();
            touch_feedback();
        } else if !crate::field_controls::inside_wheel(x, y, wf, hf) {
            crate::field_controls::close();
        }
        SWALLOWED_INPUTS.lock().unwrap().get_or_insert_with(std::collections::HashSet::new).insert(id);
        return
    }
    if crate::touch_controls::wheel_open() && *WHEEL_PTR.lock().unwrap() != Some(id) && !on_movement {
        crate::touch_controls::set_wheel_open(false);
        WHEEL_PTR.lock().unwrap().take();
    }
    if on_movement {
        *MOVEMENT_PTR.lock().unwrap() = Some(id);
        movement_update(x, y);
        return
    }
    if hit.is_some_and(|i| crate::touch_controls::controls()[i].name == crate::field_controls::NAME) {
        crate::field_controls::toggle();
        touch_feedback();
        SWALLOWED_INPUTS.lock().unwrap().get_or_insert_with(std::collections::HashSet::new).insert(id);
        return
    }
    if hit.is_none()&&crate::touch_navigation::active(){
        if !crate::touch_navigation::begin(id,x,y,hf){SWALLOWED_INPUTS.lock().unwrap().get_or_insert_with(std::collections::HashSet::new).insert(id);}return
    }
    match hit {
        Some(index) => {
            if crate::touch_controls::controls()[index].name == crate::touch_controls::ROTATE_NAME {
                queue_rotate_at_last_game_touch();
                SWALLOWED_INPUTS.lock().unwrap().get_or_insert_with(std::collections::HashSet::new).insert(id);
                touch_feedback();
                return;
            }
            if crate::touch_controls::controls()[index].name == crate::touch_controls::PARTY_NAME {
                // Holding it opens the party wheel instead of pressing a key of its own.
                crate::touch_controls::set_wheel_open(true);
                *WHEEL_PTR.lock().unwrap() = Some(id);
            } else {
                let first = {
                    let mut pointers = POINTER_CONTROLS.lock().unwrap();
                    let pointers = pointers.get_or_insert_with(HashMap::new);
                    let first = !pointers.values().any(|held| *held == index);
                    pointers.insert(id, index);
                    first
                };
                if first { control_key_down(index); }
            }
            touch_feedback();
        },
        None => {
            // The game asks for text through its own dialog, and touching it opens the system
            // keyboard. The only clickable thing the game has there is its "Aceptar" box, so a touch
            // anywhere else is free; touching "Aceptar" still confirms, because the game keeps the tap.
            if crate::touch_controls::text_entry_open() {
                ime_set(true);
            }
            mouse_down(id, x, y)
        },
    }
}

pub(super) fn pointer_up(id: i32, x: f32, y: f32) {
    if BOX_TOUCH.lock().unwrap().end(id, crate::box_touch::Point(x, y), Instant::now()) { return }
    if crate::touch_navigation::owns(id){
        if let Some((x,y))=crate::touch_navigation::end(id,x,y){
            platform::push_input(ramen::platform::ios::InputEvent::PointerMoved{x,y});
        }
        trim_navigation_taps();
        return
    }
    let closes_wheel = {
        let mut owner = WHEEL_PTR.lock().unwrap();
        if *owner == Some(id) { *owner = None; true } else { false }
    };
    if closes_wheel {
        // The key only goes out now, on the release, and only if a slot was picked. Letting go over
        // the middle of the wheel, or letting go without moving at all, sends nothing.
        let selected = crate::touch_controls::wheel_selected();
        if selected >= 0 {
            tap_key(crate::touch_controls::PICKER_KEYS[selected as usize]);
        }
        crate::touch_controls::set_wheel_open(false);
        return
    }
    if SWALLOWED_INPUTS.lock().unwrap().get_or_insert_with(std::collections::HashSet::new).remove(&id) {
        return
    }
    if is_movement_pointer(id) {
        movement_release();
        return
    }
    let index = POINTER_CONTROLS.lock().unwrap().get_or_insert_with(HashMap::new).remove(&id);
    match index {
        Some(index) => {
            let still_held = POINTER_CONTROLS.lock().unwrap().as_ref().is_some_and(|p| p.values().any(|held| *held == index));
            if !still_held { control_key_up(index); }
        },
        None => mouse_up(id, x, y),
    }
}

/// A real tap lasts ~100 ms, but a quick one can deliver press and release inside a single poll.
/// The game reads the mouse once per frame, so such a tap is simply missed — that is why clicking
/// the game's menus with the finger felt random. Holding the release briefly makes taps behave
/// like real mouse clicks.
const MIN_TAP: Duration = Duration::from_millis(70);

/// The game decides which menu entry is under the cursor while it *moves*; a click only confirms
/// the current one. A finger sends move and press together, so the press used to land on whatever
/// was selected before. Delivering the move a hair earlier gives the game that frame.
const HOVER_DELAY: Duration = Duration::from_millis(45);

static MOUSE_PRIMARY_HELD: Mutex<Option<(f32, f32)>> = Mutex::new(None);
static MOUSE_DOWN_AT: Mutex<Vec<(i32, Instant)>> = Mutex::new(Vec::new());
static DELAYED_UPS: Mutex<Vec<(Instant, f32, f32)>> = Mutex::new(Vec::new());
static DELAYED_DOWNS: Mutex<Vec<(Instant, f32, f32)>> = Mutex::new(Vec::new());

/// Last place the finger touched the game itself, not a button.
static LAST_GAME_TOUCH: Mutex<Option<(f32, f32)>> = Mutex::new(None);
const ROTATE_DELAY: Duration = Duration::from_millis(350);
static PENDING_ROTATE: Mutex<Option<(Instant, f32, f32)>> = Mutex::new(None);

fn mouse_down(id: i32, x: f32, y: f32) {
    *LAST_GAME_TOUCH.lock().unwrap() = Some((x, y));
    let deliver_at = Instant::now() + HOVER_DELAY;
    let mut downs = MOUSE_DOWN_AT.lock().unwrap();
    downs.retain(|(pointer, _)| *pointer != id);
    downs.push((id, deliver_at));
    drop(downs);
    // The move goes out now; the press follows on a later poll so the hover is in place first.
    platform::push_input(ramen::platform::ios::InputEvent::PointerMoved { x, y });
    DELAYED_DOWNS.lock().unwrap().push((deliver_at, x, y));
}

fn mouse_up(id: i32, x: f32, y: f32) {
    let pressed_at = {
        let mut downs = MOUSE_DOWN_AT.lock().unwrap();
        let at = downs.iter().find(|(pointer, _)| *pointer == id).map(|(_, at)| *at);
        downs.retain(|(pointer, _)| *pointer != id);
        at
    };
    let deadline = pressed_at.map(|at| at + MIN_TAP).unwrap_or_else(Instant::now);
    if deadline > Instant::now() {
        DELAYED_UPS.lock().unwrap().push((deadline, x, y));
    } else {
        MOUSE_PRIMARY_HELD.lock().unwrap().take();
        platform::push_input(ramen::platform::ios::InputEvent::PointerUp { x, y, button: 0 });
    }
}

fn right_click_at(x: f32, y: f32) {
    use ramen::platform::ios::InputEvent;
    platform::push_input(InputEvent::PointerMoved { x, y });
    platform::push_input(InputEvent::PointerDown { x, y, button: 2 });
    platform::push_input(InputEvent::PointerUp { x, y, button: 2 });
}

fn queue_rotate_at_last_game_touch() {
    if let Some((x, y)) = *LAST_GAME_TOUCH.lock().unwrap() {
        *PENDING_ROTATE.lock().unwrap() = Some((Instant::now() + ROTATE_DELAY, x, y));
        eprintln!("[puzzle] girar encolado en {},{}", x, y);
    }
}

fn flush_pending_rotate() {
    let mut pending = PENDING_ROTATE.lock().unwrap();
    let Some((at, x, y)) = *pending else { return };
    if Instant::now() < at {
        return;
    }
    *pending = None;
    eprintln!("[puzzle] girar enviado en {},{}", x, y);
    right_click_at(x, y);
}

/// Delivers the presses and releases that were held back to make a short tap a proper click.
fn flush_delayed_mouse() {
    let now = Instant::now();
    let mut downs: Vec<(f32, f32)> = Vec::new();
    DELAYED_DOWNS.lock().unwrap().retain(|(at, x, y)| {
        if *at <= now {
            downs.push((*x, *y));
            false
        } else {
            true
        }
    });
    for (x, y) in downs {
        *MOUSE_PRIMARY_HELD.lock().unwrap() = Some((x, y));
        platform::push_input(ramen::platform::ios::InputEvent::PointerDown { x, y, button: 0 });
    }

    let mut ups: Vec<(f32, f32)> = Vec::new();
    DELAYED_UPS.lock().unwrap().retain(|(at, x, y)| {
        if *at <= now {
            ups.push((*x, *y));
            false
        } else {
            true
        }
    });
    for (x, y) in ups {
        MOUSE_PRIMARY_HELD.lock().unwrap().take();
        platform::push_input(ramen::platform::ios::InputEvent::PointerUp { x, y, button: 0 });
    }
}

fn pointer_is_control(id: i32) -> bool {
    POINTER_CONTROLS.lock().unwrap().as_ref().map(|m| m.contains_key(&id)).unwrap_or(false)
}

// --- Movement (joystick or D-pad) ---------------------------------------------------------

/// Pointer id currently driving the movement control, if any.
static MOVEMENT_PTR: Mutex<Option<i32>> = Mutex::new(None);
/// Which arrow keys the movement control is holding (bit 0 up, 1 down, 2 left, 3 right).
static MOVEMENT_STATE: std::sync::atomic::AtomicU32 = std::sync::atomic::AtomicU32::new(0);

const MOVEMENT_KEYS: [Key; 4] = [Key::UpArrow, Key::DownArrow, Key::LeftArrow, Key::RightArrow];

fn is_movement_pointer(id: i32) -> bool {
    *MOVEMENT_PTR.lock().unwrap() == Some(id)
}

/// Presses/releases the arrow keys so they match where the movement control is being pushed.
fn movement_update(x: f32, y: f32) {
    // The stick is also used to navigate an already-open bag.
    // Don't revoke the bag transition while the player scrolls its item list.
    if !crate::touch_navigation::bag_open(){crate::touch_navigation::disarm_bag();}
    use std::sync::atomic::Ordering;
    let (w, h) = platform::window_size();
    let (wf, hf) = (w as f32, h as f32);
    if wf <= 0.0 || hf <= 0.0 {
        return
    }
    let dirs = crate::touch_controls::movement_dirs(x / wf, y / hf, wf, hf);
    crate::touch_controls::set_move_dirs(dirs);
    let mut state = MOVEMENT_STATE.load(Ordering::Relaxed);
    let mut new_direction = false;
    for (i, &on) in dirs.iter().enumerate() {
        let bit = 1u32 << i;
        if on != (state & bit != 0) {
            if on {
                if !crate::touch_controls::key_held_by_buttons(MOVEMENT_KEYS[i]) {
                    platform::push_input(ramen::platform::ios::InputEvent::KeyDown { key: MOVEMENT_KEYS[i], text: None });
                }
                new_direction = true;
                state |= bit;
            } else {
                if !crate::touch_controls::key_held_by_buttons(MOVEMENT_KEYS[i]) {
                    platform::push_input(ramen::platform::ios::InputEvent::KeyUp { key: MOVEMENT_KEYS[i] });
                }
                state &= !bit;
            }
        }
    }
    MOVEMENT_STATE.store(state, Ordering::Relaxed);
    // The D-pad gives a short tap each time a direction is marked; the analog stick stays silent.
    if new_direction && crate::touch_controls::move_mode() == crate::touch_controls::MoveMode::Dpad {
        touch_feedback();
    }

    // Clamp the drawn knob to the ring.
    let classic = crate::touch_controls::overlay_style() == crate::touch_controls::OverlayStyle::Classic;
    let (jcx, jcy) = if classic { crate::touch_controls::joystick_center_in_window(wf, hf) } else { crate::touch_controls::movement_center() };
    let r = if classic { crate::touch_controls::joystick_radius() } else { crate::touch_controls::movement_radius() } * hf;
    let mut dx = (x - jcx * wf) / r;
    let mut dy = (y - jcy * hf) / r;
    let len = (dx * dx + dy * dy).sqrt();
    if len > 1.0 {
        dx /= len;
        dy /= len;
    }
    crate::touch_controls::set_movement_offset(dx, dy);
}

fn movement_release() {
    use std::sync::atomic::Ordering;
    crate::touch_controls::set_move_dirs([false; 4]);
    let state = MOVEMENT_STATE.swap(0, Ordering::Relaxed);
    for i in 0..4 {
        if state & (1 << i) != 0 && !crate::touch_controls::key_held_by_buttons(MOVEMENT_KEYS[i]) {
            platform::push_input(ramen::platform::ios::InputEvent::KeyUp { key: MOVEMENT_KEYS[i] });
        }
    }
    crate::touch_controls::set_movement_offset(0.0, 0.0);
    *MOVEMENT_PTR.lock().unwrap() = None;
}

fn release_touch_profile() {
    let (box_id, box_events) = BOX_TOUCH.lock().unwrap().cancel();
    emit_box_events(box_events);
    let held = POINTER_CONTROLS.lock().unwrap().take().unwrap_or_default();
    let mut swallowed = SWALLOWED_INPUTS.lock().unwrap();
    let ids = swallowed.get_or_insert_with(std::collections::HashSet::new);
    if let Some(id) = box_id { ids.insert(id); }
    // No delayed click from the old screen may leak into the newly opened box/menu.
    DELAYED_DOWNS.lock().unwrap().clear();
    DELAYED_UPS.lock().unwrap().clear();
    for (id, _) in MOUSE_DOWN_AT.lock().unwrap().drain(..) { ids.insert(id); }
    if let Some((x, y)) = MOUSE_PRIMARY_HELD.lock().unwrap().take() {
        platform::push_input(ramen::platform::ios::InputEvent::PointerUp { x, y, button: 0 });
    }
    for (id, index) in held {
        control_key_up(index);
        ids.insert(id);
    }
    if let Some(id) = *MOVEMENT_PTR.lock().unwrap() { ids.insert(id); }
    movement_release();
    if let Some(id) = WHEEL_PTR.lock().unwrap().take() { ids.insert(id); }
    crate::touch_controls::set_wheel_open(false);
    crate::field_controls::close();
    TAPS.lock().unwrap().queued.clear();
    if let Some(id)=crate::touch_navigation::cancel(){ids.insert(id);}
    if let Some((x,y))=crate::touch_navigation::cancel_pointer(){
        platform::push_input(ramen::platform::ios::InputEvent::PointerUp{x,y,button:0});
    }
}


pub(super) fn pointer_move(id: i32, x: f32, y: f32) {
    if SWALLOWED_INPUTS.lock().unwrap().as_ref().is_some_and(|ids| ids.contains(&id)) { return; }
    if BOX_TOUCH.lock().unwrap().moved(id, crate::box_touch::Point(x,y), Instant::now()) { return; }
    if crate::touch_navigation::moved(id,x,y) { return; }
    if *WHEEL_PTR.lock().unwrap() == Some(id) {
        let (w,h)=platform::window_size();
        if w>0 && h>0 {
            let picked=crate::touch_controls::wheel_item_at(x/w as f32,y/h as f32,w as f32,h as f32);
            crate::touch_controls::set_wheel_selected(picked.map(|i|i as i32).unwrap_or(-1));
        }
    } else if is_movement_pointer(id) { movement_update(x,y); }
    else if !pointer_is_control(id) {
        *LAST_GAME_TOUCH.lock().unwrap()=Some((x,y));
        platform::push_input(platform::InputEvent::PointerMoved{x,y});
    }
}
static CONTEXT: Mutex<Option<(u8,crate::touch_navigation::Identity,bool)>> = Mutex::new(None);
static TEXT_OPEN: std::sync::atomic::AtomicBool = std::sync::atomic::AtomicBool::new(false);
pub(super) fn pump() {
    let current=(crate::touch_controls::current_context(),crate::touch_navigation::identity(),box_touch_active());
    let changed=CONTEXT.lock().unwrap().replace(current).is_some_and(|old|old!=current);
    if changed { release_touch_profile(); }
    let events=BOX_TOUCH.lock().unwrap().poll(Instant::now(),crate::touch_controls::box_carrying(),crate::touch_controls::box_resting_target());
    emit_box_events(events);
    if let Some(key)=crate::touch_navigation::next_key(){tap_navigation_key(key);}
    flush_tapped_keys();
    if let Some((down,x,y))=crate::touch_navigation::next_pointer(){
        platform::push_input(if down {platform::InputEvent::PointerDown{x,y,button:0}} else {platform::InputEvent::PointerUp{x,y,button:0}});
    }
    for index in crate::touch_controls::stale_pressed(){control_key_up(index);}
    flush_delayed_mouse();flush_pending_rotate();
    let text=crate::touch_controls::text_entry_open();
    if TEXT_OPEN.swap(text,std::sync::atomic::Ordering::Relaxed)!=text {ime_set(text);}
}
pub(super) fn cancel() {
    release_touch_profile();
    if let Some(ids)=SWALLOWED_INPUTS.lock().unwrap().as_mut(){ids.clear();}
    let mut taps=TAPS.lock().unwrap();
    if let TapPhase::Pressed{key,..}=taps.phase {platform::push_input(platform::InputEvent::KeyUp{key});}
    taps.phase=TapPhase::Idle;taps.queued.clear();
    *PENDING_ROTATE.lock().unwrap()=None;
    *LAST_GAME_TOUCH.lock().unwrap()=None;
    *CONTEXT.lock().unwrap()=None;
    TEXT_OPEN.store(false,std::sync::atomic::Ordering::Relaxed);
}
