//! Digital eight-way input and an independent visual spring for the touchscreen stick.
use std::f32::consts::{FRAC_PI_4, PI, TAU};

pub const ACTIVATE: f32 = 0.10;
const RELEASE: f32 = 0.07;
const ANGLE_HYSTERESIS: f32 = 5.0 * PI / 180.0;

/// [up, down, left, right], with radial and angular hysteresis to avoid chatter.
pub fn directions(dx: f32, dy: f32, previous: [bool; 4]) -> [bool; 4] {
    let distance = dx.hypot(dy);
    let px = previous[3] as i8 - previous[2] as i8;
    let py = previous[1] as i8 - previous[0] as i8;
    let held = (px != 0 || py != 0)
        && !(previous[0] && previous[1]) && !(previous[2] && previous[3]);
    if !distance.is_finite() || distance <= if held { RELEASE } else { ACTIVATE } {
        return [false; 4]
    }
    let angle = dy.atan2(dx);
    if held {
        let old_angle = (py as f32).atan2(px as f32);
        let delta = (angle - old_angle + PI).rem_euclid(TAU) - PI;
        if delta.abs() <= FRAC_PI_4 * 0.5 + ANGLE_HYSTERESIS { return previous }
    }
    match (angle / FRAC_PI_4).round() as i32 % 8 {
        0 => [false, false, false, true],
        1 | -7 => [false, true, false, true],
        2 | -6 => [false, true, false, false],
        3 | -5 => [false, true, true, false],
        4 | -4 => [false, false, true, false],
        5 | -3 => [true, false, true, false],
        6 | -2 => [true, false, false, false],
        _ => [true, false, false, true],
    }
}

/// Critically damped, frame-rate independent motion. Never feeds back into key input.
pub struct StickSpring { position: [f32; 2], velocity: [f32; 2] }
impl StickSpring {
    pub const fn new() -> Self { Self { position: [0.0; 2], velocity: [0.0; 2] } }
    pub fn reset(&mut self) { *self = Self::new(); }
    pub fn step(&mut self, target: (f32, f32), elapsed: f32) -> (f32, f32) {
        if !elapsed.is_finite() || elapsed <= 0.0 {
            return (self.position[0], self.position[1])
        }
        let target = if target.0.is_finite() && target.1.is_finite() { target } else { (0.0, 0.0) };
        let len = target.0.hypot(target.1).max(1.0);
        let target = [target.0 / len, target.1 / len];
        let speed = if target == [0.0, 0.0] { 25.0 } else { 45.0 };
        let dt = elapsed.min(0.25);
        let decay = (-speed * dt).exp();
        for (i, &goal) in target.iter().enumerate() {
            let offset = self.position[i] - goal;
            let impulse = self.velocity[i] + speed * offset;
            self.position[i] = goal + (offset + impulse * dt) * decay;
            self.velocity[i] = (self.velocity[i] - speed * impulse * dt) * decay;
        }
        let len = self.position[0].hypot(self.position[1]).max(1.0);
        for p in &mut self.position { *p /= len; }
        if target == [0.0, 0.0] && self.position[0].hypot(self.position[1]) < 0.001
            && self.velocity[0].hypot(self.velocity[1]) < 0.02 { self.reset(); }
        (self.position[0], self.position[1])
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    const R: [bool; 4] = [false, false, false, true];
    const DR: [bool; 4] = [false, true, false, true];
    fn at(degrees: f32, previous: [bool; 4]) -> [bool; 4] {
        let a = degrees.to_radians(); directions(a.cos(), a.sin(), previous)
    }
    #[test]
    fn eight_sectors_at_small_and_full_travel() {
        let expected = [R, DR, [false,true,false,false], [false,true,true,false],
            [false,false,true,false], [true,false,true,false], [true,false,false,false],
            [true,false,false,true]];
        for radius in [0.11, 0.4, 1.0] {
            for (i, want) in expected.iter().enumerate() {
                let a = i as f32 * FRAC_PI_4;
                assert_eq!(directions(radius*a.cos(), radius*a.sin(), [false;4]), *want);
            }
        }
    }
    #[test]
    fn sector_edges_do_not_chatter_including_angle_wrap() {
        assert_eq!(at(24.0, R), R);
        assert_eq!(at(29.0, R), DR);
        assert_eq!(at(21.0, DR), DR);
        assert_eq!(at(16.0, DR), R);
        let left = [false,false,true,false];
        assert_eq!(at(-179.0, left), left);
    }
    #[test]
    fn activation_release_and_invalid_input() {
        assert_eq!(directions(0.09,0.0,[false;4]), [false;4]);
        assert_eq!(directions(0.11,0.0,[false;4]), R);
        assert_eq!(directions(0.08,0.0,R), R);
        assert_eq!(directions(0.06,0.0,R), [false;4]);
        for bad in [f32::NAN, f32::INFINITY] {
            assert_eq!(directions(bad,0.0,R), [false;4]);
        }
    }
    #[test]
    fn visual_spring_settles_without_overshoot_at_different_frame_rates() {
        for fps in [30,60,120,240] {
            let mut spring = StickSpring::new();
            let mut last = 0.0;
            for _ in 0..fps {
                let (x,y) = spring.step((1.0,0.0), 1.0/fps as f32);
                assert!(x >= last && x <= 1.0 && y == 0.0);
                last = x;
            }
            assert!(last > 0.999);
            let mut point = (0.0,0.0);
            for _ in 0..fps { point = spring.step((0.0,0.0), 1.0/fps as f32); }
            assert_eq!(point, (0.0,0.0));
        }
    }
    #[test]
    fn input_is_immediate_while_cap_stays_inside_base() {
        let mut spring = StickSpring::new();
        assert_eq!(directions(1.0,0.0,[false;4]), R);
        assert!(spring.step((1.0,0.0), 1.0/60.0).0 < 1.0);
        assert_eq!(directions(0.0,0.0,R), [false;4]);
        for i in 0..200 {
            let target = if i%2==0 { (8.0,-6.0) } else { (-9.0,3.0) };
            let (x,y) = spring.step(target, 1.0/60.0);
            assert!(x.hypot(y) <= 1.000001);
        }
        spring.reset();
        assert_eq!(spring.step((f32::NAN,0.0), 1.0/60.0), (0.0,0.0));
    }
}
