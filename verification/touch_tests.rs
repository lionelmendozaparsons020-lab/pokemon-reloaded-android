#![allow(dead_code)]
extern crate self as ramen;
#[path = "../vendor/ramen/src/input.rs"] pub mod input;
#[path = "../src/OpenGMK/gm8emulator/src/touch_controls.rs"] mod touch_controls;
#[path = "../src/OpenGMK/gm8emulator/src/touch_appearance.rs"] mod touch_appearance;
#[path = "../src/OpenGMK/gm8emulator/src/field_controls.rs"] mod field_controls;
#[path = "../src/OpenGMK/gm8emulator/src/touch_navigation.rs"] mod touch_navigation;
#[path = "../src/OpenGMK/gm8emulator/src/box_touch.rs"] mod box_touch;

#[path = "../src/OpenGMK/gm8emulator/src/touch_stick.rs"] mod touch_stick;

#[test]
fn profiles_keep_automatic_switching_and_correct_key8_in_both_visual_styles() {
    use touch_controls as tc;
    tc::set_overlay_style(tc::OverlayStyle::Classic);
    tc::set_room(100);
    tc::set_modal_id(-1);
    let idx = |name: &str| tc::controls().iter().position(|c| c.name == name).unwrap();
    let eight = idx("alpha8");
    assert_eq!(tc::controls()[eight].key, input::Key::Alpha8);
    assert!(matches!(tc::controls()[eight].label, tc::Label::Text("8")));
    for style in ["modern", "classic"] {
        touch_appearance::load(&format!("touch-appearance-v1\nstyle={style}\n"));
        assert!(tc::is_active(eight));
        assert!(tc::is_active(idx("sel_world")));
        for n in 1..=7 { assert!(!tc::is_active(idx(&format!("alpha{n}")))); }
        match tc::window_shape_for(eight, 1536.0, 720.0) {
            tc::Shape::Circle { cx, cy, r } => {
                assert!((cx - 0.228).abs() < 0.0001);
                assert!((cy - 0.05).abs() < 0.0001);
                assert!((r - 0.022).abs() < 0.0001);
            },
            _ => panic!("button8 must retain the standard circular touch target"),
        }
        assert_eq!(tc::hit(0.228, 0.05, 1536.0, 720.0), Some(eight));
    }
    touch_navigation::report(200, -1, true);
    tc::set_room(200);
    assert_eq!(tc::current_context(), tc::MENU_NAV);
    assert!(tc::is_active(idx("z")) && tc::is_active(idx("x")));
    assert!(tc::movement_active());
    assert!(!tc::is_active(eight) && !tc::is_active(idx("v")));
    touch_navigation::report(8, -1, false);
    tc::set_room(8);
    tc::set_box_open(true);
    assert_eq!(tc::current_context(), tc::MENU);
    assert!(!tc::is_active(idx("z")) && !tc::movement_active());
    for style in ["classic", "modern"] {
        touch_appearance::load(&format!("touch-appearance-v1\nstyle={style}\n"));
        for (i, control) in tc::controls().iter().enumerate() {
            assert!(!control.name.starts_with("box_"));
            assert!(!tc::is_active(i));
        }
    }
    for room in [7,5,6] {
        touch_navigation::report(room, -1, false);
        tc::set_room(room);
        assert_eq!(tc::current_context(), tc::MENU_NAV);
        assert!(tc::is_active(idx("z")) && tc::is_active(idx("x")) && tc::movement_active());
    }
    touch_navigation::report(8, -1, false);
    tc::set_room(8);
    assert_eq!(tc::current_context(), tc::MENU);
    tc::set_modal_id(7778);
    assert_eq!(tc::current_context(), tc::MENU_NAV);
    tc::set_modal_id(-1);
    tc::set_box_open(false);
    touch_navigation::report(47, -1, false);
    tc::set_room(47);
    assert_eq!(tc::current_context(), tc::BATTLE);
    assert!(tc::is_active(idx("pkmn")));
    assert!(!tc::is_active(idx("sel_world")) && !tc::is_active(eight));
    touch_navigation::report(100, -1, false);
    tc::set_room(100);
    assert!(tc::is_active(eight));
    tc::set_move_mode(tc::MoveMode::Joystick);
    for (w,h) in [(1536.0,720.0),(2400.0,1080.0),(1600.0,1200.0)] {
        let (cx,cy) = tc::joystick_center_in_window(w,h);
        let r = tc::joystick_radius()*h;
        tc::set_move_dirs([false;4]);
        assert_eq!(tc::movement_dirs(cx+0.08*r/w,cy-0.08*r/h,w,h), [true,false,false,true]);
        tc::set_move_dirs([true,false,false,true]);
        assert_eq!(tc::movement_dirs(cx,cy,w,h), [false;4]);
    }
    tc::set_move_dirs([false;4]);
    tc::set_room(tc::PUZZLE_ROOM);
    for name in [tc::ROTATE_NAME,"f1","x"] { assert!(tc::is_active(idx(name))); }
    tc::set_room(100);
}

#[test]
fn small_touch_stick_motion_preserves_gamepad_deadzone() {
    use touch_controls::{touch_stick_dirs as touch, stick_dirs as pad};
    assert_eq!(touch(0.0,0.0),[false;4]);
    assert_eq!(touch(0.11,0.0),[false,false,false,true]);
    assert_eq!(touch(0.0,-0.11),[true,false,false,false]);
    assert_eq!(touch(-0.08,0.08),[false,true,true,false]);
    assert_eq!(touch(f32::NAN,0.0),[false;4]);
    assert_eq!(pad(0.11,0.0),[false;4]);
}


#[test]
fn exploration_sel_uses_seven_reachable_hexagon_centers() {
    let (w,h)=(2400.0,1080.0);
    let (left,top,width,height)=field_controls::rect(w,h);
    for (index, (sx,sy)) in field_controls::CENTERS.iter().copied().enumerate() {
        let x=left+(sx-144.0)/966.0*width;
        let y=top+(sy-116.0)/1022.0*height;
        assert!(field_controls::inside_wheel(x,y,w,h));
        assert_eq!(field_controls::item_at(x,y,w,h),Some(index));
    }
    assert_eq!(field_controls::item_at(0.0,0.0,w,h),None);
    assert_eq!(field_controls::item_at(-3.0,-2.0,w,h),None);
}

#[test]
fn bag_modal_in_same_room_restores_navigation_then_exits_cleanly() {
    use touch_controls as tc;
    tc::set_room(100);
    tc::set_modal_id(-1);
    touch_navigation::report(100,-1,false);
    assert!(!touch_navigation::bag_open());
    touch_navigation::arm_bag();
    touch_navigation::report(100,8192,false);
    tc::set_modal_id(8192);
    assert!(touch_navigation::bag_open());
    assert_eq!(tc::current_context(),tc::MENU_NAV);
    let mut gesture=touch_navigation::Gesture::new(101,100.0,200.0,720.0,touch_navigation::identity());
    assert_eq!(gesture.moved(100.0,198.0),0);
    assert!(gesture.moved(100.0,100.0)>0,"swiping up navigates down through items");
    assert!(gesture.moved(100.0,220.0)<0,"swiping down navigates up through items");
    touch_navigation::report(100,-1,false);
    tc::set_modal_id(-1);
    assert!(!touch_navigation::bag_open());
    assert_eq!(tc::current_context(),tc::WORLD);
}


#[test]
fn finger_swipes_scroll_rapidly_without_large_delayed_key_backlog() {
    use touch_controls as tc;
    use touch_navigation as nav;
    use input::Key;
    tc::set_room(100);
    tc::set_box_open(false);
    tc::set_modal_id(7778); // the Enter/N item-list navigation profile
    nav::report(100,7778,false);
    nav::cancel();
    assert!(nav::active());

    // A short drag already produces an arrow. Previously a full ~40px
    // movement on a 720px window was needed, followed by 55ms pacing.
    let mut gesture=nav::Gesture::new(21,300.0,500.0,720.0,nav::identity());
    assert_eq!(gesture.moved(300.0,492.0),0);
    assert_eq!(gesture.moved(300.0,464.0),1);
    assert!(gesture.dragged);

    assert!(nav::begin(99,300.0,500.0,720.0));
    assert!(nav::moved(99,300.0,425.0));
    assert_eq!(nav::next_key(),Some(Key::DownArrow));

    // A reversal discards obsolete direction requests rather than moving
    // the selection in the wrong direction long after the finger turns.
    assert!(nav::moved(99,300.0,590.0));
    assert!(nav::end(99,300.0,630.0).is_none());
    let mut rest=Vec::new();
    for _ in 0..5 {
        std::thread::sleep(std::time::Duration::from_millis(14));
        if let Some(key)=nav::next_key(){rest.push(key);}
    }
    assert!(rest.len()<=3,"released gestures must not leave a long backlog");
    assert!(rest.iter().all(|key|*key==Key::UpArrow));
    nav::cancel();
    tc::set_modal_id(-1);
    nav::report(100,-1,false);
}

#[test]
fn modern_v2_keeps_original_and_classic_visual_styles_available() {
    use touch_appearance::{Style, settings, load};
    load("touch-appearance-v1\nstyle=modern_v2\nanimations=1\nhaptics=1\n");
    assert!(settings().style == Style::ModernV2);
    load("touch-appearance-v1\nstyle=modern\n");
    assert!(settings().style == Style::Modern);
    load("touch-appearance-v1\nstyle=classic\n");
    assert!(settings().style == Style::Classic);
    load("touch-appearance-v1\nstyle=modern\n");
}
