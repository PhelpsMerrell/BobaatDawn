//
//  ForestNPC.swift
//  BobaAtDawn
//
//  DEPRECATED — replaced by NPC/ForestNPCEntity.swift
//
//  This file now contains only a typealias so that any remaining
//  references to `ForestNPC` still compile. Migrate all call-sites
//  to use `ForestNPCEntity` directly, then delete this file via Xcode.
//

import SpriteKit

/// Backward-compatibility alias. Use `ForestNPCEntity` in all new code.
@available(*, deprecated, renamed: "ForestNPCEntity")
typealias ForestNPC = ForestNPCEntity
