//! Recognize taps before generating a click; scrolling emits only directional keys.
use std::{collections::VecDeque,sync::{Mutex,atomic::{AtomicU64,Ordering}},time::{Duration,Instant}};
use ramen::input::Key;
#[derive(Clone,Copy,Debug,PartialEq,Eq)]
pub struct Identity{pub room:i32,pub modal:i32}
static IDENTITY:Mutex<Identity>=Mutex::new(Identity{room:-1,modal:-1});
static BAG:Mutex<Option<i32>>=Mutex::new(None);
// A bag opened as a modal stays active only while that modal is present.
static BAG_MODAL:Mutex<Option<i32>>=Mutex::new(None);
static ARMED:Mutex<Option<(Identity,Instant)>>=Mutex::new(None);
static FRAME:AtomicU64=AtomicU64::new(0);
pub fn identity()->Identity{*IDENTITY.lock().unwrap()}
/// Monotonic game report tick, used to keep synthetic key presses visible to the game.
pub fn frame()->u64{FRAME.load(Ordering::Relaxed)}
pub fn arm_bag(){*ARMED.lock().unwrap()=Some((identity(),Instant::now()));}
pub fn disarm_bag(){*ARMED.lock().unwrap()=None;}
pub fn report(room:i32,modal:i32,named_bag:bool){
    *IDENTITY.lock().unwrap()=Identity{room,modal};
    let mut bag=BAG.lock().unwrap();
    let mut bag_modal=BAG_MODAL.lock().unwrap();
    if bag.is_some_and(|id|id!=room) || bag_modal.is_some_and(|id|id!=modal){
        *bag=None;
        *bag_modal=None;
    }
    let mut armed=ARMED.lock().unwrap();
    if let Some((old,at))=*armed{
        if at.elapsed()>Duration::from_secs(2){*armed=None;}
        else if old.room!=room {
            *bag=Some(room);
            *bag_modal=None;
            *armed=None;
        } else if old.modal!=modal && modal>=0 {
            // Some backpacks appear as a list modal inside the *same* room.
            *bag=Some(room);
            *bag_modal=Some(modal);
            *armed=None;
        }
    }
    if named_bag {
        *bag=Some(room);
        *bag_modal=None;
    }
    FRAME.fetch_add(1,Ordering::Relaxed);
}
pub fn bag_open()->bool{BAG.lock().unwrap().is_some_and(|id|id==identity().room)}
pub fn active()->bool{crate::touch_controls::current_context()==crate::touch_controls::MENU_NAV&&!crate::touch_controls::info_window_open()}
#[derive(Clone,Debug)]
pub struct Gesture{pub id:i32,pub context:Identity,start:(f32,f32),last_y:f32,residual:f32,pub dragged:bool,slop:f32,step:f32}
impl Gesture{
    pub fn new(id:i32,x:f32,y:f32,height:f32,context:Identity)->Self{Self{id,context,start:(x,y),last_y:y,residual:0.,dragged:false,slop:(height*0.012).clamp(7.,18.),step:(height*0.032).clamp(15.,38.)}}
    pub fn moved(&mut self,x:f32,y:f32)->i32{
        let dx=x-self.start.0;let dy=y-self.start.1;
        if !self.dragged&&dx*dx+dy*dy>self.slop*self.slop{self.dragged=true;}
        if !self.dragged{return 0}
        self.residual+=self.last_y-y;self.last_y=y;
        let steps=(self.residual/self.step).trunc().clamp(-12.,12.)as i32;self.residual-=steps as f32*self.step;steps
    }
}
static GESTURE:Mutex<Option<Gesture>>=Mutex::new(None);
/// Buffered positions are bounded so the list cannot keep scrolling long after the finger.
struct Pending{context:Identity,keys:VecDeque<Key>}
static PENDING:Mutex<Option<Pending>>=Mutex::new(None);
const MAX_SCROLL_BACKLOG:usize=6;
fn enqueue_scroll(context:Identity,steps:i32){
    if steps==0{return}
    let key=if steps>0{Key::DownArrow}else{Key::UpArrow};
    let mut pending=PENDING.lock().unwrap();
    let p=pending.get_or_insert_with(||Pending{context,keys:VecDeque::new()});
    if p.context!=context{
        *p=Pending{context,keys:VecDeque::new()};
    }
    // Reverse direction immediately: stale steps from the previous swipe are discarded.
    if p.keys.back().is_some_and(|previous|*previous!=key){p.keys.clear();}
    for _ in 0..steps.unsigned_abs().min(MAX_SCROLL_BACKLOG as u32){
        if p.keys.len()>=MAX_SCROLL_BACKLOG{break}
        p.keys.push_back(key);
    }
}
pub fn owns(id:i32)->bool{GESTURE.lock().unwrap().as_ref().is_some_and(|g|g.id==id)}
pub fn begin(id:i32,x:f32,y:f32,height:f32)->bool{
    let mut g=GESTURE.lock().unwrap();if g.is_some() || TAP.lock().unwrap().is_some(){return false}
    *PENDING.lock().unwrap()=None;*g=Some(Gesture::new(id,x,y,height,identity()));true
}
pub fn moved(id:i32,x:f32,y:f32)->bool{
    let mut guard=GESTURE.lock().unwrap();let Some(g)=guard.as_mut().filter(|g|g.id==id)else{return false};
    let steps=g.moved(x,y);
    enqueue_scroll(g.context,steps);
    true
}
/// A stationary tap still clicks a menu entry. A drag only scrolls.
pub fn end(id:i32,x:f32,y:f32)->Option<(f32,f32)>{
    let mut guard=GESTURE.lock().unwrap();if !guard.as_ref().is_some_and(|g|g.id==id){return None}
    let mut g=guard.take().unwrap();
    let steps=g.moved(x,y);
    enqueue_scroll(g.context,steps);
    if g.dragged||g.context!=identity()||!active(){return None}
    *PENDING.lock().unwrap()=None;
    *TAP.lock().unwrap()=Some(Tap{context:g.context,x,y,pressed:false,due:Instant::now()+Duration::from_millis(45)});
    Some((x,y))
}
/// The Android pump controls key timing. Never apply an additional 55ms wait here.
pub fn next_key()->Option<Key>{
    let mut guard=PENDING.lock().unwrap();let p=guard.as_mut()?;
    if p.context!=identity()||!active(){*guard=None;return None}
    let key=p.keys.pop_front();if p.keys.is_empty(){*guard=None;}key
}
pub fn cancel()->Option<i32>{*PENDING.lock().unwrap()=None;GESTURE.lock().unwrap().take().map(|g|g.id)}

struct Tap {context:Identity,x:f32,y:f32,pressed:bool,due:Instant}
static TAP:Mutex<Option<Tap>>=Mutex::new(None);
/// Hover -> primary down -> primary up. Time-based release is essential: the game may
/// wait for mouse-up inside a modal loop without redrawing another frame.
pub fn next_pointer()->Option<(bool,f32,f32)>{
    let mut guard=TAP.lock().unwrap();let tap=guard.as_mut()?;
    if tap.context!=identity() || !active(){
        let release=tap.pressed.then_some((false,tap.x,tap.y));*guard=None;return release
    }
    if Instant::now()<tap.due{return None}
    let event=(!tap.pressed,tap.x,tap.y);
    if tap.pressed{*guard=None;}else{tap.pressed=true;tap.due=Instant::now()+Duration::from_millis(70);}
    Some(event)
}
pub fn cancel_pointer()->Option<(f32,f32)>{
    TAP.lock().unwrap().take().filter(|t|t.pressed).map(|t|(t.x,t.y))
}
