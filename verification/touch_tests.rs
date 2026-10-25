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
fn exploration_sel_hexagons_match_each_number_and_close_on_demand() {
    use touch_controls as tc;
    use field_controls as field;
    tc::set_overlay_style(tc::OverlayStyle::Modern);
    tc::set_pad_active(false);
    tc::set_info_window(false);
    tc::set_modal_id(-1);
    tc::set_room(100);
    field::close();
    field::toggle();
    assert!(field::open(), "exploration SEL must open");
    let (ww, wh) = (1536.0, 720.0);
    let (left, top, width, height) = field::rect(ww, wh);
    let expected = [
        input::Key::Alpha1, input::Key::Alpha2, input::Key::Alpha3,
        input::Key::Alpha4, input::Key::Alpha5, input::Key::Alpha6, input::Key::Alpha7,
    ];
    for (i, &(sx, sy)) in field::CENTERS.iter().enumerate() {
        // Invert the same artwork crop used by item_at.
        let x = left + (sx - 144.0) / 966.0 * width;
        let y = top + (sy - 116.0) / 1022.0 * height;
        assert_eq!(field::item_at(x, y, ww, wh), Some(i), "hexagon {i}");
        assert_eq!(field::KEYS[i], expected[i], "wrong key for hexagon {i}");
    }
    field::close();
    assert!(!field::open());
}

#[test]
fn bag_navigation_follows_the_opened_room_and_keeps_movement() {
    use touch_controls as tc;
    tc::set_overlay_style(tc::OverlayStyle::Modern);
    tc::set_pad_active(false);
    tc::set_info_window(false);
    tc::set_modal_id(-1);
    touch_navigation::report(100, -1, false);
    tc::set_room(100);
    touch_navigation::arm_bag();
    touch_navigation::report(200, -1, false);
    tc::set_room(200);
    assert!(touch_navigation::bag_open());
    assert!(touch_navigation::active());
    assert_eq!(tc::current_context(), tc::MENU_NAV);
    assert!(tc::movement_active(), "bag must keep the joystick enabled");
    touch_navigation::report(100, -1, false);
    tc::set_room(100);
    assert!(!touch_navigation::bag_open(), "leaving bag should restore normal controls");
}
