use crate::helper::window_chrome::text_color;
use nostalre_game::event::GameEvent;
use nostalre_ui::draw::{self, DrawCall, TextureRef};
use nostalre_ui::frame::{UiFrame, WidgetId};
use nostalre_ui::rect::Rect;

const MENU_BASE_ID: u32 = 4700;
const ITEM_W: f32 = 120.0;
const ITEM_H: f32 = 18.0;

#[derive(Clone)]
pub enum ContextMenuAction {
    InviteToParty {
        target_aid: u32,
    },
    /// Whisper `party` (a population shell then holds still and accepts) and send the party invite
    RecruitToParty {
        target_aid: u32,
        name: String,
    },
    RequestTrade {
        target_aid: u32,
    },
    AdoptBaby {
        target_aid: u32,
    },
    Whisper {
        name: String,
    },
    ChangeGuildPosition {
        aid: u32,
        gid: u32,
        position_id: i32,
    },
    ExpelFromGuild {
        aid: u32,
        gid: u32,
        name: String,
    },
    GuildLeave,
    GuildInvite {
        target_aid: u32,
    },
    GuildAlly {
        target_aid: u32,
    },
    GuildHostile {
        target_aid: u32,
    },
    CompanionShowInfo {
        is_mercenary: bool,
    },
    CompanionFeed,
    CompanionStandby {
        is_mercenary: bool,
    },
    CompanionPatrol {
        is_mercenary: bool,
    },
    CompanionAiConfig,
    KickFromChatRoom {
        name: String,
    },
    ChangeChatOwner {
        name: String,
    },
    PetShowInfo,
    PetFeed,
    PetCommand {
        csub: i8,
    },
    GiveMannerPoint {
        target_aid: u32,
        positive: bool,
    },
    AccountName {
        aid: u32,
    },
}

pub struct ContextMenuItem {
    pub label: String,
    pub action: ContextMenuAction,
}

#[derive(Default)]
pub struct ContextMenu {
    open: bool,
    x: f32,
    y: f32,
    items: Vec<ContextMenuItem>,
    /// The line the arrow keys (a controller's D-pad) have picked; Enter chooses it
    selected: Option<usize>,
}

impl ContextMenu {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn open_at(&mut self, x: f32, y: f32, items: Vec<ContextMenuItem>) {
        if items.is_empty() {
            return;
        }
        self.open = true;
        self.x = x;
        self.y = y;
        self.items = items;
        self.selected = None;
    }

    /// Opened from a controller or keys: the first line starts picked
    pub fn open_selected(&mut self, x: f32, y: f32, items: Vec<ContextMenuItem>) {
        self.open_at(x, y, items);
        self.selected = self.open.then_some(0);
    }

    pub fn close(&mut self) {
        self.open = false;
        self.items.clear();
    }

    pub fn is_open(&self) -> bool {
        self.open
    }

    pub fn build(&mut self, ui: &mut UiFrame) -> Vec<GameEvent> {
        if !self.open {
            return Vec::new();
        }
        let tc = text_color(false);
        let mut events = Vec::new();

        let menu_h = self.items.len() as f32 * ITEM_H;
        let panel = Rect::new(self.x, self.y, ITEM_W, menu_h);

        ui.begin_popup_layer(panel);
        crate::helper::fallback::panel(ui, panel.x, panel.y, panel.w, panel.h);

        let last = self.items.len() - 1;
        if ui.ctx.key_up {
            self.selected = Some(self.selected.map_or(last, |i| if i == 0 { last } else { i - 1 }));
        }
        if ui.ctx.key_down {
            self.selected = Some(self.selected.map_or(0, |i| if i == last { 0 } else { i + 1 }));
        }
        let mut clicked_item = None;
        if ui.ctx.key_enter && let Some(i) = self.selected {
            clicked_item = Some(self.items[i].action.clone());
        }
        let escape = ui.ctx.key_escape;
        let mut any_hovered = false;
        for (idx, item) in self.items.iter().enumerate() {
            let iy = self.y + idx as f32 * ITEM_H;
            let rect = Rect::new(self.x, iy, ITEM_W, ITEM_H);
            let resp = ui.interact(WidgetId(MENU_BASE_ID + idx as u32), rect);
            if resp.hovered() {
                any_hovered = true;
                ui.any_interactive_hovered = true;
            }
            if resp.hovered() || self.selected == Some(idx) {
                let (v, i) =
                    draw::quad_vertices(rect.x, rect.y, rect.w, rect.h, [0.72, 0.79, 0.93, 1.0]);
                ui.draw_calls.push(DrawCall {
                    vertices: v.into(),
                    indices: i.into(),
                    texture: TextureRef::White,
                });
            }
            ui.text(rect.x + 6.0, rect.y + 13.0, &item.label, tc);
            if resp.clicked() {
                clicked_item = Some(item.action.clone());
            }
        }

        if let Some(action) = clicked_item {
            match action {
                ContextMenuAction::InviteToParty { target_aid } => {
                    events.push(GameEvent::RequestPartyInvite { target_aid });
                }
                ContextMenuAction::RecruitToParty { target_aid, name } => {
                    events.push(GameEvent::RequestSendWhisper {
                        name,
                        message: "party".to_string(),
                    });
                    events.push(GameEvent::RequestPartyInvite { target_aid });
                }
                ContextMenuAction::RequestTrade { target_aid } => {
                    events.push(GameEvent::RequestExchangeItem { target_aid });
                }
                ContextMenuAction::AdoptBaby { target_aid } => {
                    events.push(GameEvent::RequestAdoption { target_aid });
                }
                ContextMenuAction::Whisper { name } => {
                    events.push(GameEvent::RequestWhisper { name });
                }
                ContextMenuAction::ChangeGuildPosition {
                    aid,
                    gid,
                    position_id,
                } => {
                    events.push(GameEvent::RequestChangeMemberPosition {
                        aid,
                        gid,
                        position_id,
                    });
                }
                ContextMenuAction::ExpelFromGuild { aid, gid, name } => {
                    events.push(GameEvent::RequestGuildExpel { aid, gid, name });
                }
                ContextMenuAction::GuildLeave => {
                    events.push(GameEvent::RequestGuildLeave);
                }
                ContextMenuAction::GuildInvite { target_aid } => {
                    events.push(GameEvent::RequestGuildInvite { target_aid });
                }
                ContextMenuAction::GuildAlly { target_aid } => {
                    events.push(GameEvent::RequestGuildAlly { target_aid });
                }
                ContextMenuAction::GuildHostile { target_aid } => {
                    events.push(GameEvent::RequestGuildHostile { target_aid });
                }
                ContextMenuAction::CompanionShowInfo { is_mercenary } => {
                    events.push(if is_mercenary {
                        GameEvent::ToggleMercenaryWindow
                    } else {
                        GameEvent::ToggleHomunculusWindow
                    });
                }
                ContextMenuAction::CompanionFeed => {
                    events.push(GameEvent::RequestHomunMenu { command: 1 });
                }
                ContextMenuAction::CompanionStandby { is_mercenary } => {
                    events.push(GameEvent::ToggleCompanionStandby { is_mercenary });
                }
                ContextMenuAction::CompanionPatrol { is_mercenary } => {
                    events.push(GameEvent::ToggleCompanionPatrol { is_mercenary });
                }
                ContextMenuAction::CompanionAiConfig => {
                    events.push(GameEvent::ToggleCompanionAiConfig);
                }
                ContextMenuAction::KickFromChatRoom { name } => {
                    events.push(GameEvent::RequestKickChatMember { name });
                }
                ContextMenuAction::ChangeChatOwner { name } => {
                    events.push(GameEvent::RequestChangeChatOwner { name });
                }
                ContextMenuAction::PetShowInfo => {
                    events.push(GameEvent::RequestPetCommand { csub: 0 });
                }
                ContextMenuAction::PetFeed => {
                    events.push(GameEvent::RequestPetFeed);
                }
                ContextMenuAction::PetCommand { csub } => {
                    events.push(GameEvent::RequestPetCommand { csub });
                }
                ContextMenuAction::GiveMannerPoint {
                    target_aid,
                    positive,
                } => {
                    events.push(GameEvent::RequestMannerPoint {
                        target_aid,
                        positive,
                    });
                }
                ContextMenuAction::AccountName { aid } => {
                    events.push(GameEvent::RequestAccountName { aid });
                }
            }
            self.close();
        } else if escape || (ui.ctx.mouse_pressed && !any_hovered) {
            self.close();
        }

        ui.end_popup_layer();
        events
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    use nostalre_ui::context::UiContext;
    use nostalre_ui::state::StateCache;
    use nostalre_ui::test_support::test_frame;

    #[test]
    fn a_press_the_world_consumed_still_closes_the_menu() {
        let mut state = StateCache::new();
        let mut menu = ContextMenu::new();
        menu.open_at(
            100.0,
            100.0,
            vec![ContextMenuItem {
                label: "Whisper".to_string(),
                action: ContextMenuAction::Whisper {
                    name: "someone".to_string(),
                },
            }],
        );

        let mut ctx = UiContext::new(800.0, 600.0);
        ctx.mouse_x = 400.0;
        ctx.mouse_y = 400.0;
        ctx.mouse_pressed = true;
        ctx.mouse_clicked = false;
        let mut ui = test_frame(&mut ctx, &mut state);
        menu.build(&mut ui);

        assert!(!menu.is_open());
    }

    #[test]
    fn keys_pick_a_line_and_recruit_whispers_then_invites() {
        let mut state = StateCache::new();
        let mut menu = ContextMenu::new();
        menu.open_selected(
            100.0,
            100.0,
            vec![
                ContextMenuItem {
                    label: "Whisper".to_string(),
                    action: ContextMenuAction::Whisper { name: "Elisin".to_string() },
                },
                ContextMenuItem {
                    label: "Recruit to Party".to_string(),
                    action: ContextMenuAction::RecruitToParty { target_aid: 7, name: "Elisin".to_string() },
                },
            ],
        );

        let mut ctx = UiContext::new(800.0, 600.0);
        ctx.key_down = true;
        let mut ui = test_frame(&mut ctx, &mut state);
        assert!(menu.build(&mut ui).is_empty());
        assert!(menu.is_open());

        let mut ctx = UiContext::new(800.0, 600.0);
        ctx.key_enter = true;
        let mut ui = test_frame(&mut ctx, &mut state);
        let events = menu.build(&mut ui);
        assert!(matches!(&events[..], [
            GameEvent::RequestSendWhisper { name, message },
            GameEvent::RequestPartyInvite { target_aid: 7 },
        ] if name == "Elisin" && message == "party"));
        assert!(!menu.is_open());
    }
}
