use super::storage_path;
use std::fs;
pub(super) fn load_touch() {
    let path = storage_path("touch.conf");
    let Ok(text) = fs::read_to_string(&path) else { return };
    eprintln!("[overlay] leyendo {}", path.display());
    crate::touch_controls::clear_layout();
    let mut positions: Vec<(String, f32, f32)> = Vec::new();
    let mut sizes: Vec<(String, f32)> = Vec::new();
    for line in text.lines() {
        let line = line.trim();
        if line.is_empty() || line.starts_with('#') {
            continue
        }
        let Some((name, value)) = line.split_once('=') else { continue };
        let (name, value) = (name.trim(), value.trim());
        match name {
            "style" => crate::touch_controls::set_overlay_style(match value {
                "classic" => crate::touch_controls::OverlayStyle::Classic,
                "none" => crate::touch_controls::OverlayStyle::None,
                _ => crate::touch_controls::OverlayStyle::New,
            }),
            "move" => crate::touch_controls::set_move_mode(if value == "dpad" {
                crate::touch_controls::MoveMode::Dpad
            } else {
                crate::touch_controls::MoveMode::Joystick
            }),
            "scale" => {
                if let Ok(scale) = value.parse::<f32>() {
                    crate::touch_controls::set_ui_scale(scale);
                }
            },
            "opacity" => {
                if let Ok(opacity) = value.parse::<f32>() {
                    crate::touch_controls::set_sprite_opacity(opacity);
                }
            },
            _ => {
                if let Some(target) = name.strip_prefix("pos.") {
                    let mut parts = value.split(',');
                    if let (Some(cx), Some(cy)) = (parts.next(), parts.next()) {
                        if let (Ok(cx), Ok(cy)) = (cx.trim().parse::<f32>(), cy.trim().parse::<f32>()) {
                            positions.push((target.to_string(), cx, cy));
                        }
                    }
                } else if let Some(target) = name.strip_prefix("size.") {
                    if let Ok(scale) = value.parse::<f32>() {
                        sizes.push((target.to_string(), scale));
                    }
                }
            },
        }
    }
    for (name, cx, cy) in &positions {
        let scale = sizes.iter().find(|(other, _)| other == name).map(|(_, scale)| *scale).unwrap_or(1.0);
        crate::touch_controls::set_placement(name, *cx, *cy, scale);
    }
    for (name, scale) in &sizes {
        if positions.iter().any(|(other, _, _)| other == name) {
            continue
        }
        let (cx, cy) = crate::touch_controls::default_center(name).unwrap_or((0.5, 0.5));
        crate::touch_controls::set_placement(name, cx, cy, *scale);
    }
    let style = match crate::touch_controls::overlay_style() {
        crate::touch_controls::OverlayStyle::New => "new",
        crate::touch_controls::OverlayStyle::Classic => "classic",
        crate::touch_controls::OverlayStyle::None => "none",
    };
    let movement = match crate::touch_controls::move_mode() {
        crate::touch_controls::MoveMode::Joystick => "joystick",
        crate::touch_controls::MoveMode::Dpad => "dpad",
    };
    eprintln!(
        "[overlay] estilo={} move={} escala={} controles={}",
        style,
        movement,
        crate::touch_controls::ui_scale(),
        positions.len().max(sizes.len())
    );
}
