//! Runtime fix-ups for bugs in the game's own GML.
//!
//! The game file is never modified: when a script is compiled, its source is swapped here for a
//! corrected version. Keep the list short, and document what each entry changes and why.

use std::sync::atomic::{AtomicBool, Ordering};
static MOD_MODE: AtomicBool = AtomicBool::new(false);

#[cfg(target_os = "android")]
mod mod_saves;

#[cfg(test)]
fn set_mod_mode(on: bool) {
    MOD_MODE.store(on, Ordering::Relaxed);
}

/// Returns a corrected source for `name`, or `None` to compile the game's original.
pub fn fixup(name: &str, source: &str) -> Option<String> {
    #[cfg(target_os = "android")]
    mod_saves::initialize_once(&MOD_MODE);
    match name {
        // The title menu and the options screen draw their entries horizontally centred on x=160
        // (so the text spans roughly x=110..210) but only accept clicks inside
        // `mouse_x >= 62 && mouse_x <= 178`. The right half of every entry is dead, and a click
        // there confirms whatever entry was selected before — which looks like the game jumping
        // to a different option. Widen the box to cover the text as drawn.
        "MouseActionsInicioControl" | "OptionsControlMouse" => {
            Some(source.replace("mouse_x>=62 && mouse_x<=178", "mouse_x>=80 && mouse_x<=240"))
        },

        // Original F3 commands only. Experimental extensions triggered a
        // documented anomaly in the original game and are disabled.
        "ExecuteCheat" if MOD_MODE.load(Ordering::Relaxed) => {
            const F3: &str = r#"Ch= ex(7754,ex(9868,9),"",0,13);cheat=string_upper(Ch);"#;
            if !source.contains(F3)
                || !source.contains(r#"if(cheat="INCONSCIENTE")"#)
                || !source.contains("global.numcheats+=1;") {
                return None;
            }
            const ACTIONS: &str = r#"
                if(cheat="RAD100K"){
                    if(!instance_exists((3)) || !instance_exists((16)))exit;
                    if(global.dinero<999999)with((16)){
                        ex(7736,min(100000,999999-global.dinero));
                        global.numcheats+=1;
                    }
                    exit;
                }
                if(cheat="RADITEM"){
                    if(!instance_exists((3)) || !instance_exists((16)))exit;
                    with((16)){if(ex(8963,1,10))global.numcheats+=1;}
                    exit;
                }
                if(string_copy(cheat,1,7)="RADITEM"){
                    if(!instance_exists((3)) || !instance_exists((16)))exit;
                    txt1=string_copy(cheat,8,string_length(cheat)-7);
                    H=string_pos("X",txt1);
                    if(H<=1 || H>=string_length(txt1))exit;
                    txt2=string_copy(txt1,1,H-1);
                    str=string_copy(txt1,H+1,string_length(txt1)-H);
                    if(string_digits(txt2)!=txt2 || string_digits(str)!=str)exit;
                    i=real(txt2);
                    j=real(str);
                    if(i<1 || i>821 || j<1 || j>99)exit;
                    if(!ex(7502,i) && !ex(7507,i))exit;
                    with((16)){if(ex(8963,i,j))global.numcheats+=1;}
                    exit;
                }
            "#;
            Some(source.replacen(F3, &format!("{}{}", F3, ACTIONS), 1))
        },
        // Reloaded limits Master Balls held/used to those awarded by story
        // events. CodMb reports "Corrupción D...H..." even if the ball
        // inventory and serialized save are internally consistent. Allow the
        // experimental mod profile's ordinary extra Master Balls, while
        // preserving the deliberate protection sentinel values above 1000.
        // The normal profile keeps the original CodMb script unchanged.
        "CodMb" if MOD_MODE.load(Ordering::Relaxed) => {
            const QUOTA_CHECK: &str = "if(has>dis)ex(9669,ex(9876,ex(9863,6845),string(has),string(dis)));";
            const COUNT: &str = "has=ex(8815,4)+ex(8816,4);";
            const SENTINEL: &str = "if(global.pkdexC[944]=true){has=4062+11;dis=4;}";
            if !source.contains(QUOTA_CHECK)
                || !source.contains(COUNT)
                || !source.contains(SENTINEL)
                || !source.contains("return has<=dis;") {
                return None;
            }
            // Ordinary Master Ball count is never above 999 under the game's
            // own bag limits. Sentinel counts >=1000 remain unmodified.
            Some(source.replacen(
                QUOTA_CHECK,
                &format!("if(has>dis && has<=999)dis=has; {}", QUOTA_CHECK),
                1,
            ))
        },
        _ => None,
    }
}

#[cfg(test)]
mod tests {
    use super::{fixup, set_mod_mode};
    #[test]
    fn mods_enabled_only_for_isolated_mode() {
        let src = r#"if(cheat="INCONSCIENTE"){} Ch= ex(7754,ex(9868,9),"",0,13);cheat=string_upper(Ch); global.numcheats+=1;"#;
        set_mod_mode(false);
        assert!(fixup("ExecuteCheat", src).is_none());
        set_mod_mode(true);
        let changed = fixup("ExecuteCheat", src).unwrap();
        assert!(changed.contains("with((16))"));
        assert!(changed.contains("ex(8963,i,j)"));
        assert!(changed.contains("ex(7736,min("));
        assert!(fixup("ExecuteCheat", "wrong edition").is_none());
        set_mod_mode(false);
    }
    #[test]
    fn master_ball_allowance_only_in_mod_profile_and_preserves_sentinels() {
        let original = r#"var dis,has; dis=0; has=ex(8815,4)+ex(8816,4); if(global.pkdexC[944]=true){has=4062+11;dis=4;} if(has>dis)ex(9669,ex(9876,ex(9863,6845),string(has),string(dis))); return has<=dis;"#;
        set_mod_mode(false);
        assert!(fixup("CodMb", original).is_none());
        set_mod_mode(true);
        let modified = fixup("CodMb", original).unwrap();
        assert!(modified.contains("if(has>dis && has<=999)dis=has;"));
        assert!(modified.contains("if(global.pkdexC[944]=true){has=4062+11;dis=4;}"));
        assert!(modified.contains("return has<=dis;"));
        assert!(fixup("CodMb", "unknown older game version").is_none());
        set_mod_mode(false);
    }

}
