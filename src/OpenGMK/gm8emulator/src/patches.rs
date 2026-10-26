//! Runtime fix-ups for bugs in the game's own GML.
//!
//! The game file is never modified: when a script is compiled, its source is swapped here for a
//! corrected version. Keep the list short, and document what each entry changes and why.

/// Returns a corrected source for `name`, or `None` to compile the game's original.
pub fn fixup(name: &str, source: &str) -> Option<String> {
    match name {
        // The title menu and the options screen draw their entries horizontally centred on x=160
        // (so the text spans roughly x=110..210) but only accept clicks inside
        // `mouse_x >= 62 && mouse_x <= 178`. The right half of every entry is dead, and a click
        // there confirms whatever entry was selected before — which looks like the game jumping
        // to a different option. Widen the box to cover the text as drawn.
        "MouseActionsInicioControl" | "OptionsControlMouse" => {
            Some(source.replace("mouse_x>=62 && mouse_x<=178", "mouse_x>=80 && mouse_x<=240"))
        },

        // Pokémon Reloaded The Last Beta 1.9.2.2 only. The game already has
        // anti-tamper witnesses: NEVER edit dinero/ObItem arrays directly here.
        // Call the game's transaction scripts so they recompute their witnesses.
        // Nothing here suppresses anomaly detection or modifies save files.
        "ExecuteCheat" => {
            const PROMPT: &str = r#"Ch= ex(7754,ex(9868,9),"",0,13);cheat=string_upper(Ch);"#;
            if !source.contains(PROMPT)
                || !source.contains(r#"if(cheat="INCONSCIENTE")"#)
                || !source.contains("global.numcheats+=1;")
            {
                return None;
            }
            let actions = r#"
                // Commands are synchronous but MUST NOT open a second blocking modal
                // on the same frame as GetDialogString(F3). Otherwise the Android
                // renderer can appear frozen while audio continues to play.
                // Use only in-game security-aware transaction scripts.
                if(cheat="RAD100K"){
                    if(!instance_exists((3)) || !instance_exists((16)))exit;
                    if(global.wait!=false)exit;
                    if(global.dinero<999999){
                        ex(7736,min(100000,999999-global.dinero));
                        global.numcheats+=1;
                    }
                    exit;
                }
                // Fast path: give ten balls with no nested numeric dialogs.
                if(cheat="RADITEM"){
                    if(!instance_exists((3)) || !instance_exists((16)))exit;
                    if(global.wait!=false)exit;
                    if(ex(8963,1,10))global.numcheats+=1;
                    exit;
                }
                // User chooses item and quantity in a SINGLE F3 string:
                // RADITEM1X10, RADITEM13X99, RADITEM821X1, etc.
                // Length never exceeds the 13-character F3 input limit.
                if(string_copy(cheat,1,7)="RADITEM"){
                    if(!instance_exists((3)) || !instance_exists((16)))exit;
                    if(global.wait!=false)exit;
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
                    if(ex(8963,i,j))global.numcheats+=1;
                    exit;
                }
            "#;
            Some(source.replacen(PROMPT, &format!("{}{}", PROMPT, actions), 1))
        },
        _ => None,
    }
}

#[cfg(test)]
mod tests {
    use super::fixup;

    #[test]
    fn only_patches_recognized_original_cheat_script() {
        let source = r#"if(cheat="INCONSCIENTE"){} Ch= ex(7754,ex(9868,9),"",0,13);cheat=string_upper(Ch); global.numcheats+=1;"#;
        let changed = fixup("ExecuteCheat", source).expect("matching script");
        let injected = changed.split("cheat=string_upper(Ch);").nth(1).unwrap();
        assert!(injected.contains("if(cheat=\"RAD100K\")"));
        assert!(injected.contains("if(cheat=\"RADITEM\")"));
        assert!(injected.contains("string_digits(txt2)"));
        assert!(injected.contains("ex(7736,min(100000,999999-global.dinero))"));
        assert!(injected.contains("ex(8963,1,10)"));
        // Never open a nested modal once F3 has closed.
        for dangerous in ["ex(7753,", "ex(7754,", "ex(9669,", "ex(9671,"] {
            assert!(!injected.contains(dangerous), "unexpected nested dialog: {}", dangerous);
        }
        assert!(fixup("ExecuteCheat", "unknown game script").is_none());
        assert!(fixup("AnotherScript", source).is_none());
    }
}
