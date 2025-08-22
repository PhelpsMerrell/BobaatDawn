//
//  ServiceSetup.swift
//  BobaAtDawn
//
//  Sets up dependency injection container for the game
//

import Foundation

class ServiceSetup {
    
    static func createGameServices() -> GameServiceContainer {
        let container = GameServiceContainer()
        
        // Register core services as singletons
        container.registerSingleton(ConfigurationService.self) {
            return StandardConfigurationService()
        }
        
        container.registerSingleton(TimeService.self) {
            return StandardTimeService()
        }
        
        container.registerSingleton(GridService.self) {
            return GridWorld()
        }
        
        container.registerSingleton(SceneTransitionService.self) {
            let configService = container.resolve(ConfigurationService.self)
            return StandardSceneTransitionService(configService: configService)
        }
        
        container.registerSingleton(InputService.self) {
            let configService = container.resolve(ConfigurationService.self)
            return StandardInputService(configService: configService)
        }
        
        container.registerSingleton(AnimationService.self) {
            let configService = container.resolve(ConfigurationService.self)
            return StandardAnimationService(configService: configService)
        }
        
        // Register NPC service with dependencies
        container.register(NPCService.self) {
            let timeService = container.resolve(TimeService.self)
            let gridService = container.resolve(GridService.self)
            return StandardNPCService(gridService: gridService, timeService: timeService)
        }
        
        print("🎯 Game services registered successfully")
        return container
    }
}
