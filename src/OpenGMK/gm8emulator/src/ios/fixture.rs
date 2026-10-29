// Minimal original fixture, no Pokémon/game assets. Exercises the real startup path.
use gm8exe::{GameAssets, GameVersion, Colour, asset::{PascalString, Room, Sprite, Script, Sound}, settings::{Settings,GameHelpDialog}};
fn string(s:&str)->PascalString {PascalString(s.as_bytes().into())}
pub(super) fn run()->Result<(),String>{
    let sprites=(0..17).map(|i|Some(Box::new(Sprite{
        name:string(&format!("smoke_sprite_{i}")),origin_x:0,origin_y:0,
        frames:vec![gm8exe::asset::sprite::Frame{width:1024,height:1024,data:vec![0x7f;1024*1024*4].into_boxed_slice()}],
        colliders:vec![],per_frame_colliders:false,
    }))).collect();
    let sounds=["snd_computer_open","snd_computer_close"].into_iter().map(|name|Some(Box::new(Sound{
        name:string(name),source:string("test.wav"),extension:string(".wav"),data:Some(Box::new([0u8;4])),
        kind:gm8exe::asset::sound::SoundKind::Normal,volume:1.0,pan:0.0,preload:true,
        fx:gm8exe::asset::sound::SoundFX{chorus:false,echo:false,flanger:false,gargle:false,reverb:false}
    }))).collect();
    let room=Room{name:string("world_smoke"),caption:string("iOS startup verification"),width:320,height:240,speed:60,
        persistent:false,bg_colour:Colour::new(17,24,35,255),clear_screen:true,clear_region:true,
        creation_code:string("global.smoke_value = smoke_proc();"),backgrounds:vec![],views_enabled:false,views:vec![],
        instances:vec![],tiles:vec![],uses_810_features:false,uses_811_features:false};
    let mut rooms=Vec::new();rooms.resize_with(101,||None);rooms[100]=Some(Box::new(room));
    let assets=GameAssets{
        triggers:vec![],constants:vec![],extensions:vec![],sprites,sounds,backgrounds:vec![],paths:vec![],
        scripts:vec![Some(Box::new(Script{name:string("smoke_proc"),source:string("var n; n=0; repeat(100) { n+=1; } return n;")}))],
        fonts:vec![],timelines:vec![],objects:vec![],rooms,included_files:vec![],version:GameVersion::GameMaker8_1,
        dx_dll:vec![],ico_file_raw:None,
        help_dialog:GameHelpDialog{bg_colour:Colour::new(0,0,0,255),new_window:false,caption:string(""),left:0,top:0,width:320,height:240,border:false,resizable:false,window_on_top:false,freeze_game:false,info:string("")},
        last_instance_id:100000,last_tile_id:10000000,library_init_strings:vec![],room_order:vec![100],
        settings:Settings{fullscreen: false,
scaling: -1,
interpolate_pixels: false,
clear_colour: 0,
allow_resize: false,
window_on_top: false,
dont_draw_border: false,
dont_show_buttons: false,
display_cursor: false,
freeze_on_lose_focus: false,
disable_screensaver: false,
force_cpu_render: false,
set_resolution: false,
colour_depth: 0,
resolution: 0,
frequency: 0,
vsync: false,
esc_close_game: false,
treat_close_as_esc: false,
f1_help_menu: false,
f4_fullscreen_toggle: false,
f5_save_f6_load: false,
f9_screenshot: false,
priority: 0,
custom_load_image: None,
transparent: false,
translucency: 0,
loading_bar: 0,
backdata: None,
frontdata: None,
scale_progress_bar: false,
show_error_messages: true,
log_errors: true,
always_abort: false,
zero_uninitialized_vars: true,
error_on_uninitialized_args: false,
swap_creation_events: false},game_id:1234,guid:[0;4],
    };
    let root=super::storage_dir().join("smoke-fixture");std::fs::create_dir_all(&root).map_err(|e|e.to_string())?;
    let mut game=crate::game::Game::launch(assets,root.join("fixture.exe"),vec![],None,encoding_rs::SHIFT_JIS,true,0,false,crate::game::PlayType::Normal).map_err(|e|e.to_string())?;
    game.init().map_err(|e|e.to_string())?;
    // Real startup reached the first room after the same malformed WAV warnings as the report.
    for _ in 0..5 { game.frame().map_err(|e|e.to_string())?; }
    super::touch::cancel();super::platform::drain_pending_input();
    use crate::touch_controls as tc;
    let (w,h)=super::platform::window_size();let (w,h)=(w as f32,h as f32);
    let z=tc::controls().iter().position(|c|c.name=="z").ok_or("Falta botón Z")?;
    let (zx,zy)=match tc::window_shape_for(z,w,h) {tc::Shape::Circle{cx,cy,..}|tc::Shape::Rect{cx,cy,..}=>(cx*w,cy*h)};
    let (cx,cy)=tc::joystick_center_in_window(w,h);let r=tc::joystick_radius()*h;
    super::touch::pointer_down(11,cx*w+r*0.65,cy*h);
    super::touch::pointer_down(12,zx,zy);
    super::touch::pointer_up(12,zx,zy);
    super::touch::pointer_up(11,cx*w+r*0.65,cy*h);
    let events=super::platform::drain_pending_input();
    use super::platform::InputEvent;use ramen::input::Key;
    for (key,down) in [(Key::RightArrow,true),(Key::Z,true),(Key::Z,false),(Key::RightArrow,false)] {
        if !events.iter().any(|e|match e{InputEvent::KeyDown{key:k,..}=>down&&*k==key,InputEvent::KeyUp{key:k}=>!down&&*k==key,_=>false}){return Err(format!("Multitouch incompleto: {events:?}"));}
    }
    super::stage("Prueba de controles");
    eprintln!("IOS_STARTUP_OK: Game::launch, invalid WAV recovery, two atlases, scripts, room, frames and Android multitouch controls");
    for _ in 0..240 {game.frame().map_err(|e|e.to_string())?;std::thread::sleep(std::time::Duration::from_millis(33));}
    Ok(())
}
