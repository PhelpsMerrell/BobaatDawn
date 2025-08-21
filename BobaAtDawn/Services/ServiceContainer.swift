//
//  ServiceContainer.swift
//  BobaAtDawn
//
//  Dependency injection container for game services
//

import Foundation

protocol ServiceContainer {
    func register<T>(_ type: T.Type, factory: @escaping () -> T)
    func resolve<T>(_ type: T.Type) -> T
}

class GameServiceContainer: ServiceContainer {
    private var factories: [String: () -> Any] = [:]
    private var singletons: [String: Any] = [:]
    
    func register<T>(_ type: T.Type, factory: @escaping () -> T) {
        let key = String(describing: type)
        factories[key] = factory
    }
    
    func registerSingleton<T>(_ type: T.Type, factory: @escaping () -> T) {
        let key = String(describing: type)
        factories[key] = { [weak self] in
            if let existing = self?.singletons[key] as? T {
                return existing
            } else {
                let instance = factory()
                self?.singletons[key] = instance
                return instance
            }
        }
    }
    
    func resolve<T>(_ type: T.Type) -> T {
        let key = String(describing: type)
        guard let factory = factories[key] else {
            fatalError("Service of type \(type) not registered")
        }
        
        guard let service = factory() as? T else {
            fatalError("Service factory returned wrong type for \(type)")
        }
        
        return service
    }
}
