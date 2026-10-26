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
                // Extra commands for an explicitly backed-up test save.
                // RAD100K uses GestionDinero / SetDinero, which check and renew
                // the money witness exactly as normal gameplay does.
                if(cheat="RAD100K"){
                    if(!instance_exists((3)) || !instance_exists((16)))exit;
                    if(global.dinero>=999999){ex(9669,"Ya tienes el maximo de dinero.");exit;}
                    if(global.dinero>899999){ex(9602,999999);}
                    else{ex(7736,100000);}
                    global.numcheats+=1;
                    ex(9669,"Mod: dinero entregado. Guarda tu partida.");
                    exit;
                }
                // RADITEM accepts ordinary Pokeballs/consumables only; PillaObject
                // handles the appropriate pocket and its integrity witness.
                // Reject key objects, technical machines and plot flags.
                if(cheat="RADITEM"){
                    if(!instance_exists((3)) || !instance_exists((16)))exit;
                    i=ex(7753,"ID de objeto o Pokeball:",false,1,6000);
                    if(i<=0)exit;
                    if(!ex(7502,i) && !ex(7507,i)){
                        ex(9669,"Solo se admiten Pokeballs y objetos comunes.");
                        exit;
                    }
                    j=ex(7753,"Cantidad (1-99):",false,1,99);
                    if(j<=0)exit;
                    if(ex(8963,i,j)){
                        global.numcheats+=1;
                        ex(9669,"Mod: objetos entregados. Guarda tu partida.");
                    }
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
        let new_source = fixup("ExecuteCheat", source).expect("matching script");
        assert!(new_source.contains("if(cheat=\"RAD100K\")"));
        assert!(new_source.contains("if(cheat=\"RADITEM\")"));
        assert!(new_source.contains("ex(7736,100000)"));
        assert!(new_source.contains("ex(8963,i,j)"));
        assert!(fixup("ExecuteCheat", "unknown game script").is_none());
        assert!(fixup("AnotherScript", source).is_none());
    }
}
