//
//  NPC.swift
//  BobaAtDawn
//
//  DEPRECATED — replaced by NPC/ShopNPC.swift
//
//  This file now contains only a typealias so that any remaining
//  references to `NPC` still compile. Migrate all call-sites to
//  use `ShopNPC` directly, then delete this file via Xcode.
//

import SpriteKit

/// Backward-compatibility alias. Use `ShopNPC` in all new code.
@available(*, deprecated, renamed: "ShopNPC")
typealias NPC = ShopNPC
