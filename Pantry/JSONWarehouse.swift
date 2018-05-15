//
//  JSONWarehouse.swift
//  JSONWarehouse
//
//  Created by Nick O'Neill on 10/29/15.
//  Copyright © 2015 That Thing in Swift. All rights reserved.
//

import Foundation

/**
JSONWarehouse serializes and deserializes data

A `JSONWarehouse` is passed in the init function of a struct that conforms to `Storable`
*/
open class JSONWarehouse: Warehouseable, WarehouseCacheable {
    let persistenceType: Pantry.PersistenceType
    var key: String
    var context: Any?

    public init(key: String, persistenceType: Pantry.PersistenceType) {
        self.persistenceType = persistenceType
        self.key = key
    }

    public init(context: Any, persistenceType: Pantry.PersistenceType) {
        self.persistenceType = persistenceType
        self.key = ""
        self.context = context
    }

    /**
     Retrieve a `StorableDefaultType` for a given key
     - parameter valueKey: The item's key
     - returns: T?

     - SeeAlso: `StorableDefaultType`
     */
    open func get<T: StorableDefaultType>(_ valueKey: String) -> T? {

        guard let dictionary = loadCache() as? [String: Any],
            let result = dictionary[valueKey] as? T else {
                return nil
        }
        return result
    }

    /**
     Retrieve a collection of `StorableDefaultType`s for a given key
     - parameter valueKey: The item's key
     - returns: [T]?

     - SeeAlso: `StorableDefaultType`
     */
    open func get<T: StorableDefaultType>(_ valueKey: String) -> [T]? {

        guard let dictionary = loadCache() as? [String: Any],
            let result = dictionary[valueKey] as? [Any] else {
                return nil
        }

        var unpackedItems = [T]()
        for case let item as T in result {
            unpackedItems.append(item)
        }

        return unpackedItems
    }

    /**
     Retrieve a generic object conforming to `Storable` for a given key
     - parameter valueKey: The item's key
     - returns: T?

     - SeeAlso: `Storable`
     */
    open func get<T: Storable>(_ valueKey: String) -> T? {

        guard let dictionary = loadCache() as? [String: Any],
            let result = dictionary[valueKey] else {
                return nil
        }

        let warehouse = JSONWarehouse(context: result, persistenceType: persistenceType)
        return T(warehouse: warehouse)
    }

    /**
     Retrieve a collection of generic objects conforming to `Storable` for a given key
     - parameter valueKey: The item's key
     - returns: [T]?

     - SeeAlso: `Storable`
     */
    open func get<T: Storable>(_ valueKey: String) -> [T]? {

        guard let dictionary = loadCache() as? [String: Any],
            let result = dictionary[valueKey] as? [Any] else {
                return nil
        }

        var unpackedItems = [T]()
        for case let item as [String: Any] in result {
            let warehouse = JSONWarehouse(context: item, persistenceType: persistenceType)
            if let item = T(warehouse: warehouse) {
                unpackedItems.append(item)
            }
        }

        return unpackedItems
    }

    func write(_ object: Any, expires: StorageExpiry) {
        let fileURL = self.fileURL()
        var storableDictionary: [String: Any] = [:]
        
        storableDictionary["expires"] = expires.toDate().timeIntervalSince1970
        storableDictionary["storage"] = object

        guard JSONSerialization.isValidJSONObject(storableDictionary) else {
            debugPrint("Not a valid JSON object: \(object)")
            return
        }

        do {
            let data = try JSONSerialization.data(withJSONObject: storableDictionary, options: .prettyPrinted)

            try data.write(to: fileURL, options: .atomic)
        } catch {
            debugPrint("\(error)")
        }
    }
    
    func removeCache() {
        do {
            try FileManager.default.removeItem(at: fileURL())
        } catch {
            print("error removing cache", error)
        }
    }
    
    static func removeAllCache(for persistenceType: Pantry.PersistenceType) {
        do {
            try FileManager.default.removeItem(at: fileDirectory(for: persistenceType))
        } catch {
            print("error removing all cache",error)
        }
    }
    
    func loadCache() -> Any? {
        guard context == nil else {
            return context
        }

        let fileURL = self.fileURL()

        // legacy format
        if let metaDictionary = NSDictionary(contentsOf: fileURL),
            let cache = metaDictionary["storage"] {
            return cache
        }
        
        if let data = try? Data(contentsOf: fileURL),
            let metaDictionary = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let cache = metaDictionary?["storage"] {
            return cache
        }

        if let data = try? Data(contentsOf: fileURL),
            let metaDictionary = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let cache = metaDictionary?["storage"] {
            return cache
        }

        return nil
    }
    
    func cacheExists() -> Bool {
        let fileURL = self.fileURL()
        
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return false }
        
        var optionalDictionary: [String: Any?]? = nil
        
        // legacy format
        if let dictionary = NSDictionary(contentsOf: fileURL) as? [String: Any?] {
            optionalDictionary = dictionary
        }
        
        // new format
        if let data = try? Data(contentsOf: fileURL),
        let dictionary = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            optionalDictionary = dictionary
        }
        
        guard let metaDictionary = optionalDictionary else {
            return false
        }

        guard let expires = metaDictionary["expires"] as? TimeInterval else {
            // no expire time means old cache, never expires
            return true
        }

        let nowInterval = Date().timeIntervalSince1970
        
        if expires > nowInterval {
            return true
        } else {
            removeCache()
            return false
        }
    }
    
    static func fileDirectory(for persistenceType: Pantry.PersistenceType) -> URL {
        switch persistenceType {
        case .permanent:    return JSONWarehouse.documentDirectory
        case .volatile:     return JSONWarehouse.FIXcacheDirectory
        }
    }
    
    static var documentDirectory: URL {
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        
        let writeDirectory = url.appendingPathComponent("com.thatthinginswift.pantry")
        return writeDirectory
    }
    
    static var FIXcacheDirectory: URL {
        let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        
        let writeDirectory = url.appendingPathComponent("com.thatthinginswift.pantry")
        return writeDirectory
    }
    
    func fileURL() -> URL {
        let directory: URL
        
        switch persistenceType {
        case .permanent:    directory = JSONWarehouse.documentDirectory
        case .volatile:     directory = JSONWarehouse.FIXcacheDirectory
        }
        
        let documentLocation = directory.appendingPathComponent(self.key)
        
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
        } catch {
            print("couldn't create directories to \(documentLocation)")
        }
        
        return documentLocation
    }
    
}
