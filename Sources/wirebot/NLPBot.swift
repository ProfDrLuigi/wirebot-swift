//
//  NLPBot.swift
//  wirebot
//
//  Created by Rafael Warnault on 13/04/2020.
//  Copyright © 2020 Read-Write. All rights reserved.
//

import Foundation
import WiredSwift
import FeedKit
import NaturalLanguage
import Fuse
import Yams


public struct File {
    var path:String!
    var name:String!
    var date:Date!
}

public protocol BotDelegate {
    func bot(_ bot:Bot, wantToSend message:String)
    func bot(_ bot:Bot, wantToSubscribeTo directory:String)
    func bot(_ bot:Bot, wantToList directory:String)
}

public extension BotDelegate {
    func bot(_ bot:Bot, wantToSend message:String) {
        
    }
    
    func bot(_ bot:Bot, wantToSubscribeTo directory:String) {
        
    }
    
    func bot(_ bot:Bot, wantToList directory:String) {
        
    }
}

public class Bot {
    public var nickname:String?
    public var primaryLanguage:String       = "english"
    public var fuzzyness:Double             = 0.68

    public var minInactvityTime:Double      = 120.0
    public var maxInactvityTime:Double      = 480.0
    public var inactivityCategories:[String] =
        ["humor", "literature", "sports", "science",
        "emotion", "computers", "history"]

    public var checkFeedTime:Double         = 900
    public var checkFeedItemLimit:Int       = 3
    
    public var latestFilesLimit:Int         = 5
    
    public var delegate:BotDelegate?
    
    let fuse = Fuse()
    var messages:[NLPMessage] = []
    var dataset:[String:[String:Any]] = [:]

    var feeds:[String] = []
    var directories:[String] = []
    
    var inactivityInterval:Double {
        get {
            return Double.random(in: minInactvityTime..<maxInactvityTime)
        }
    }
    
    var checkFeedTimer:Timer?
    var inactivityTimer:Timer?
    
    public init(withDirectory path:String, config:[String:Any]?) {        
        // init bot config
        if let v = config?["primaryLanguage"] as? String {
            self.primaryLanguage = v
        }
        
        if let v = config?["nick"] as? String {
            self.nickname = v
        }
        
        if let v = config?["fuzzyness"] as? Double {
            self.fuzzyness = v
        }
    
        if let v = config?["minInactvityTime"] as? Double {
            self.minInactvityTime = v
        }
        
        if let v = config?["maxInactvityTime"] as? Double {
            self.maxInactvityTime = v
        }
        
        if let v = config?["checkFeedTime"] as? Double {
            self.checkFeedTime = v
        }
        
        if let v = config?["checkFeedItemLimit"] as? Int {
            self.checkFeedItemLimit = v
        }
        
        if let v = config?["latestFilesLimit"] as? Int {
            self.latestFilesLimit = v
        }
        
        if let v = config?["rss_feeds"] as? [String] {
            self.feeds = v
        }

        if let v = config?["watched_directories"] as? [String] {
            self.directories = v
        }
        
        // langs
        for langName in self.subpaths(for: path) {
            self.dataset[langName] = [:]
            
            let langPath = [path, langName].joined(separator: "/")
            
            // category
            for categoryFileName in self.subpaths(for: langPath) {
                let categorytPath = [langPath, categoryFileName].joined(separator: "/")
                
                do {
                    let yamlString = try String(contentsOfFile: categorytPath, encoding: .utf8)
                    
                    let decoded = try Yams.load(yaml: yamlString) as? [String: [Any]]
                    
                    let categoryName = NSString(string: categoryFileName).deletingPathExtension
                    self.dataset[langName]![categoryName] = decoded!["conversations"]
                    
                } catch let e {
                    Logger.error(e.localizedDescription)
                }
            }
        }
        
        self.restartInactivityTimer()
        self.startCheckFeedTimer()
    }
    
        
    private func startCheckFeedTimer() {
        self.checkFeedTimer = Timer.scheduledTimer(withTimeInterval: self.checkFeedTime, repeats: true, block: { (timer) in
            self.sendFeeds()
        })
    }
    
    private func sendFeeds() {
        for feedURI in self.feeds {
            if let feedURL = URL(string: feedURI) {
                let parser = FeedParser(URL: feedURL)
                let result = parser.parse()
                switch result {
                case .success(let feed):
                    
                    // Grab the parsed feed directly
                    if let rssFeed = feed.rssFeed {
                        if let d = self.delegate {
                            d.bot(self, wantToSend: "📰 Lastest entries on \(rssFeed.title!):")
                            var text = ""
                            
                            var index = 0
                            for item in rssFeed.items! {
                                text += "- \(item.title!): \(item.link!)\n"
                                
                                index += 1
                                
                                if index >= self.checkFeedItemLimit {
                                    break
                                }
                            }
                            
                            d.bot(self, wantToSend: text)
                        }
                    }
                    
                case .failure(let error):
                    Logger.error(error.localizedDescription)
                    if let d = self.delegate {
                        d.bot(self, wantToSend: "I have a problem: \(error)")
                    }
                }
            }
        }
    }
    
    private func restartInactivityTimer() {
        if inactivityTimer != nil  {
            inactivityTimer!.invalidate()
            inactivityTimer = nil
        }
        
        inactivityTimer = Timer.scheduledTimer(withTimeInterval: self.inactivityInterval, repeats: false, block: { (timer) in
            if let langDataset = self.dataset[self.primaryLanguage] {
                let interests = [
                    langDataset["humor"],
                    langDataset["literature"],
                    langDataset["sports"],
                    langDataset["science"],
                    langDataset["emotion"],
                    langDataset["computers"],
                    langDataset["history"]
                ]
                
                if let array = interests.randomElement() as? [[String]] {
                    if let subarray = array.randomElement()?.dropFirst() {
                        let rand = Int.random(in: 0..<subarray.count)
                                                
                        var count = 0
                        for resp in subarray {
                            if let d = self.delegate {
                                d.bot(self, wantToSend: resp)
                            }
                            
                            count += 1
                            
                            if count >= rand {
                                break
                            }
                        }
                    }
                }
            }
            
            self.restartInactivityTimer()
        })
    }
    
    
    public func hi(_ nick:String) -> String? {
        if let langDataset = dataset[primaryLanguage] {
            if let array = self.array(in: langDataset, forKey: "greetings") {
                for group in array {
                    return group.dropFirst().randomElement()
                }
            }
        }
        return nil
    }
    
    public func bye(_ nick:String) -> String? {
        return nil
    }

    public func process(_ message:NLPMessage) -> String? {
        if message.lang == nil {
            return nil
        }
        
        let lang = self.lang(for: message.lang)
        
        // interest by lemmas
        for lemma in message.lemmas {
            if let response = self.match(message: message, forCategory: lemma) {
                return response
            }
        }
        
        // interest by token neighbors
        for (_, neighbors) in message.tokenNeighbors {
            for neighbor in neighbors.keys {
                if let response = self.match(message: message, forCategory: neighbor) {
                    return response
                }
            }
        }
                            
        // greetings
        if let response = self.match(message: message, forCategory: "greetings") {
            return response
        }
        
        // conversations
        if let response = self.match(message: message, forCategory: "conversations") {
            return response
        }
            
        // scann all dataset
        if let langDataset = dataset[lang] {
            for key in langDataset.keys {
                if let response = self.match(message: message, forCategory: key, customFuzzyness: 1.0) {
                    return response
                }
                
                if let response = self.match(message: message, forCategory: key) {
                    return response
                }
            }
        }
        
        return nil
    }
    
    
    private func lang(for idiom:String) -> String {
        var lang = "english"
        
        if idiom == "fr" {
            lang = "french"
        }
        else if idiom == "jp" {
            lang = "japanese"
        }
        else if idiom == "sp" {
            lang = "spanish"
        }
        else if idiom == "de" {
            lang = "german"
        }
        
        return lang
    }
    
    
    private func match(message:NLPMessage, forCategory category:String, customFuzzyness:Double = 0.68) -> String? {
        let lang = self.lang(for: message.lang)
        var input = String(message.messageText).lowercased()
        
        if message.tokens.count > 2 {
            if let newInput = NLPMessage.symbolize(input) {
                input = newInput
            }
        }
        
        if let langDataset = dataset[lang] {
            if let array = self.array(in: langDataset, forKey: category) {
                for group in array {
                    if let first = group.first {
                        var matcher = first.lowercased()
                        
                        if message.tokens.count > 2 {
                            if let newMatcher = NLPMessage.symbolize(matcher) {
                                matcher = newMatcher
                            }
                        }
                        
                        if input.contains(matcher) {
                            return group.dropFirst().randomElement()
                        }
                        
                        let f = customFuzzyness != fuzzyness ? customFuzzyness : fuzzyness
                        
                        if let result = fuse.search(input, in: matcher) {
                            if result.score > f {
                                return group.dropFirst().randomElement()
                            }
                        }
                    }
                }
            }
        }
        return nil
    }
    
    public func process(command:String) {
        if command == "/help" {
            let help = """
/help show this help message
/feeds show the latest feeds entries
/files show latest indexed files
"""
            if let d = self.delegate {
               d.bot(self, wantToSend: help)
           }
        }
        else if command == "/feeds" {
            if self.feeds.count > 0 {
                self.sendFeeds()
            } else {
                if let d = self.delegate {
                    d.bot(self, wantToSend: "Sorry, no RSS feed has been configured yet")
                }
            }
        }
        else if command == "/files" {
            if self.feeds.count > 0 {
                if let d = self.delegate {
                    for dir in self.directories {
                        d.bot(self, wantToList: dir)
                    }
                }
            } else {
                if let d = self.delegate {
                    d.bot(self, wantToSend: "Sorry, no watched directory has been configured yet")
                }
            }
        }
    }
    
    
    
    private func array(in dataset:[String:Any], forKey key:String) -> [[String]]? {
        // search for dataset neighbors
        var neighbors:[String] = []
        
        let embedding = NLEmbedding.wordEmbedding(for: .english)
        embedding?.enumerateNeighbors(for: key.lowercased(), maximumCount: 5) { (string, distance) -> Bool in
            neighbors.append(string)
            return true
        }
    
        for n in neighbors {
            if let r = dataset[n] as? [[String]] {
                return r
            }
        }
        
        return dataset[key] as? [[String]]
    }

    
    private func subpaths(for path:String) -> [String] {
        let fm = FileManager.default
        var paths:[String] = []

        do {
            let items = try fm.contentsOfDirectory(atPath: path)
            for item in items {
                if !item.starts(with: ".") {
                    paths.append(item)
                }
            }
        } catch { }
        
        return paths
    }
}

