//! Effect art loads a little each frame instead of all at once on the first map: there it took seconds on the
//! RP6, the input queue went unread and Android called the game not responding (2026-10-21). First what draws
//! wrong when missing (the hand-written effects' textures draw white, their sprites not at all), then the common
//! effects (hits, heals, level up, warps), then the player's own skills once the skill list comes, then the rest.
//! An STR effect played before its turn loads when it plays (`game_updates`), with the names tried after its
//! first.
use crate::App;
use models::enums::effect_id::EffectId;
use models::enums::skill_enums::SkillEnum;
use std::collections::{HashMap, VecDeque};
use std::time::{Duration, Instant};

/// A frame's share of loading; one item goes each frame even when it alone takes longer
const FRAME_BUDGET: Duration = Duration::from_millis(4);

/// Effects nearly every session shows soon: hits, heals, levels, refining and brewing, warps, items, MVPs
const COMMON: [EffectId; 23] = [
    EffectId::Hit1,
    EffectId::Hit2,
    EffectId::Hitline7,
    EffectId::Heal,
    EffectId::Heal2,
    EffectId::Heal3,
    EffectId::Heal4,
    EffectId::Angel,
    EffectId::Angel2,
    EffectId::Angel3,
    EffectId::Joblvup,
    EffectId::Joblvup50,
    EffectId::Refineok,
    EffectId::Refinefail,
    EffectId::Warpzone2,
    EffectId::Portal,
    EffectId::Portal2,
    EffectId::Readyportal2,
    EffectId::Teleportation2,
    EffectId::Entry2,
    EffectId::GetItem,
    EffectId::Mvp,
    EffectId::Lockon,
];

enum Asset {
    Texture(String),
    Sprite(&'static str),
    /// An STR effect: its first name, then the names tried after it
    Str(&'static [&'static str]),
}

pub(crate) struct EffectLoader {
    queue: VecDeque<Asset>,
    /// Every STR effect's names by its first, for one loaded when it plays
    str_names: HashMap<&'static str, &'static [&'static str]>,
    started: Option<Instant>,
    loaded: usize,
}

impl EffectLoader {
    pub(crate) fn new() -> Self {
        let all_strs = nostalre_game::effect::effect_str_names();
        let str_names = all_strs.iter().map(|names| (names[0], *names)).collect();
        let mut queue: VecDeque<Asset> = nostalre_game::effect::effect_texture_paths()
            .into_iter()
            .map(Asset::Texture)
            .collect();
        let mut sprites: Vec<&'static str> = nostalre_game::effect::effect_spr_paths();
        sprites.extend(nostalre_game::effect::custom_effect_sprite_paths());
        sprites.extend(nostalre_game::effect::skill_unit_sprite_paths());
        sprites.sort();
        sprites.dedup();
        queue.extend(sprites.into_iter().map(Asset::Sprite));
        let common = COMMON
            .into_iter()
            .filter_map(nostalre_game::effect::str_names_of);
        queue.extend(common.map(Asset::Str));
        // every STR at once is ~1.6 GB of GPU memory, past a 2 GB iPad's per-app limit: there the rest
        // load when they first play
        if !low_memory_device() {
            queue.extend(all_strs.into_iter().map(Asset::Str));
        }
        Self {
            queue,
            str_names,
            started: None,
            loaded: 0,
        }
    }

    /// The names an STR effect is also found under, after `name`
    pub(crate) fn other_names(&self, name: &str) -> &'static [&'static str] {
        self.str_names.get(name).map_or(&[], |names| &names[1..])
    }

    /// The player's skills come first: their STR effects go to the front of what is left
    pub(crate) fn put_skills_first(&mut self, skills: impl Iterator<Item = SkillEnum>) {
        if self.queue.is_empty() {
            return;
        }
        for skill in skills {
            let ids = nostalre_game::effect::skill_effect_ids(skill);
            for names in ids
                .into_iter()
                .filter_map(nostalre_game::effect::str_names_of)
            {
                self.queue.push_front(Asset::Str(names));
            }
        }
    }
}

/// Under 3 GiB of RAM (or NOSTALRE_LOW_MEMORY=1 to try it elsewhere)
fn low_memory_device() -> bool {
    if std::env::var_os("NOSTALRE_LOW_MEMORY").is_some_and(|v| v == "1") {
        return true;
    }
    physical_memory().is_some_and(|bytes| bytes < 3 << 30)
}

#[cfg(target_vendor = "apple")]
fn physical_memory() -> Option<u64> {
    unsafe extern "C" {
        fn sysctlbyname(name: *const std::ffi::c_char, old: *mut std::ffi::c_void, oldlen: *mut usize, new: *mut std::ffi::c_void, newlen: usize) -> i32;
    }
    let mut bytes: u64 = 0;
    let mut len = std::mem::size_of::<u64>();
    let ok = unsafe { sysctlbyname(c"hw.memsize".as_ptr(), (&raw mut bytes).cast(), &mut len, std::ptr::null_mut(), 0) } == 0;
    ok.then_some(bytes)
}

// ponytail: Apple only for now; Android/Linux could read /proc/meminfo if a small device needs it
#[cfg(not(target_vendor = "apple"))]
fn physical_memory() -> Option<u64> {
    None
}

impl App {
    /// A frame's share of the effect art; nothing once it is all in
    pub(crate) fn load_effects_in_background(&mut self) {
        let (Some(renderer), Some(grf)) = (self.renderer.as_mut(), self.grf.as_ref()) else {
            return;
        };
        let loader = &mut self.effect_loader;
        if loader.queue.is_empty() {
            return;
        }
        let start = Instant::now();
        let started = *loader.started.get_or_insert(start);
        while let Some(asset) = loader.queue.pop_front() {
            match asset {
                Asset::Texture(path) => {
                    renderer.load_effect_texture(&path, grf);
                }
                Asset::Sprite(path) => {
                    self.effect_sprites.load(
                        path,
                        grf,
                        &renderer.device.device,
                        &renderer.device.queue,
                        &renderer.texture_cache.bind_group_layout,
                    );
                }
                Asset::Str(names) => {
                    self.str_effects.load(
                        names[0],
                        &names[1..],
                        grf,
                        &mut renderer.texture_cache,
                        &renderer.device.device,
                        &renderer.device.queue,
                    );
                }
            }
            loader.loaded += 1;
            if start.elapsed() >= FRAME_BUDGET {
                break;
            }
        }
        if loader.queue.is_empty() {
            tracing::info!(
                "Effect art loaded in the background: {} items in {:.1} s",
                loader.loaded,
                started.elapsed().as_secs_f32()
            );
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_common_effects_and_every_str_are_queued() {
        let loader = EffectLoader::new();
        let strs = loader
            .queue
            .iter()
            .filter(|a| matches!(a, Asset::Str(_)))
            .count();
        assert!(strs >= loader.str_names.len());
        assert_eq!(
            loader.other_names("newfirewall"),
            &["firewall1", "firewall2"]
        );
        assert!(loader.other_names("no such effect").is_empty());
    }

    #[test]
    fn a_skill_goes_to_the_front() {
        let mut loader = EffectLoader::new();
        loader.put_skills_first(std::iter::once(SkillEnum::AlAngelus));
        assert!(matches!(loader.queue.front(), Some(Asset::Str(_))));
    }
}
