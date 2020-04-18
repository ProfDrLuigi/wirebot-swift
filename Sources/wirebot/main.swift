//
//  main.swift
//  wirebot
//
//  Created by Rafael Warnault on 10/04/2020.
//  Copyright © 2020 Read-Write. All rights reserved.
//

import Foundation
import ArgumentParser
import WiredSwift



// MARK: -

extension Process {

    public static let gitExecURL = URL(fileURLWithPath: "/usr/bin/git")

    public func clone(repo: URL, to: URL) throws {
        executableURL = Process.gitExecURL
        arguments = ["clone", repo.absoluteString, to.path]
        try run()
    }

}




// MARK: -

class Connect: ParsableCommand, ConnectionDelegate, BotDelegate {
    private static var config:[String:Any] = [:]
    
    private static var bot:Bot!
    private static var spec:P7Spec!
    private static var connection:Connection!
    
    private static var files:[File] = []
    private static var users:[UserInfo] = []
    
    @Option(help: "Config file to overwrite ~/.wirebot/wirebot.json")
    private var config_path: String?
    
    @Option(help: "Chat corpus directory to overwrite ~/.wirebot/chatterbot-corpus/chatterbot_corpus/data")
    private var corpus_path: String?
    
    @Argument(help: "Server hostname to connect")
    private var hostname: String
    
    @Argument(help: "User login")
    private var login: String
    
    @Option(help: "User password")
    private var password: String?
    
    @Option(help: "User nick")
    private var nick: String?
    
    @Option(help: "User status")
    private var status: String?

    @Option(help: "User icon (path to 32x32 png file)")
    private var icon_path: String?
    
    
    
    
    
    // MARK: -
    
    required init() {
        // do nothin here, its weird
    }
    

    
    func run() throws {
        Logger.setMaxLevel(.INFO)
        
        // init Wirebot
        self.initWirebot()
        
        guard var data_path = self.dataPath else {
            Logger.fatal("Chat corpus is missing...")
            Connect.exit(withError: nil)
        }
        
        if let customCorpusPath = self.config_path {
            data_path = customCorpusPath
        }
        
        guard let spec_path = self.specPath else {
            Logger.fatal("Wired spec is missing...")
            Connect.exit(withError: nil)
        }
        
        Connect.bot = Bot(withDirectory: data_path, config: Connect.config)
        Connect.bot.delegate = self
        
        // init config values
        if self.nick == nil {
            if let v = Connect.config["nick"] as? String {
                self.nick = v
            }
        }
        
        if self.status == nil {
            if let v = Connect.config["status"] as? String {
                self.status = v
            }
        }
        
        if self.icon_path == nil {
            if let v = Connect.config["icon"] as? String {
                self.icon_path = v
            }
        }

        
        // init Wired stack
        Connect.spec = P7Spec(withPath: spec_path)
        
        // the Wired URL to connect to
        let url = Url(withString: "wired://\(self.hostname)")
        url.login = self.login

        if let p = self.password {
            url.password = p
        }
        
        
        // init connection
        let connection      = Connection(withSpec: Connect.spec, delegate: self)
        connection.nick     = self.nick ?? "Wirebot"
        connection.status   = self.status ?? "NLP Powered"

        if let path = self.icon_path {
            let url = URL(fileURLWithPath: path)
            if let data = try? Data(contentsOf: url) {
                connection.icon = data.base64EncodedString()
            }
        }

        // perform connect
        if connection.connect(withUrl: url) {
            // we keep a reference to the working connection here
            Connect.connection = connection

            // join the public chat
            _ = connection.joinChat(chatID: 1)

            // subscribe to watched directories
            for d in Connect.bot.directories {
                self.bot(Connect.bot, wantToSubscribeTo: d)
            }

        } else {
            // not connected
            print(connection.socket.errors)
        }

        RunLoop.main.run()
    }
    
    
    
    // MARK: -
    
    func connectionDidReceiveMessage(connection: Connection, message: P7Message) {
        if message.name == "wired.chat.say" {
            if  let string = message.string(forField: "wired.chat.say"),
                let userID = message.uint32(forField: "wired.user.id") {
                if let userNick = Connect.user(withID: userID)?.nick {
                    if userID != connection.userID {
                        if string.starts(with: "/") {
                            Connect.bot.process(command: string)
                        } else {
                            let msg = NLPMessage(withMessage: string, byNick: userNick)
                            
                            if let reply = Connect.bot.process(msg) {
                                self.send(reply: reply, withSleep: true)
                            }
                        }
                    }
                }
            }
        }
        else if message.name == "wired.chat.user_list" {
            Connect.users.append(UserInfo(message: message))
        }
        else if message.name == "wired.chat.user_join" {
            Connect.users.append(UserInfo(message: message))
            
            if  let userID = message.uint32(forField: "wired.user.id") {
                if let userNick = Connect.user(withID: userID)?.nick {
                    if let hi = Connect.bot.hi(userNick) {
                        self.send(reply: "\(hi) \(userNick)", withSleep: true)
                    }
                }
            }
        }
        else if message.name == "wired.chat.user_leave" {
            if let userID = message.uint32(forField: "wired.user.id") {
                if let index = Connect.indexOf(userID: userID) {
                    Connect.users.remove(at: index)
                }
            }
        }
        else if message.name == "wired.file.directory_changed" {
            if let path = message.string(forField: "wired.file.path") {
                self.list(path: path)
            }
        }
        else if message.name == "wired.file.file_list" {
            if let path = message.string(forField: "wired.file.path") {
                if let date = message.date(forField: "wired.file.modification_time") {
                    Connect.files.append(File(path: path, name: (path as NSString).lastPathComponent, date: date))
                }
            }
        }
        else if message.name == "wired.file.file_list.done" {
            Connect.files = Connect.files.sorted(by: { $0.date > $1.date })
            
            if let f = Connect.files.first, let parent = (f.path as NSString?)?.deletingLastPathComponent {
                self.send(reply: "📂 Latest files added to « \(parent) » :")
            }
            
            let drop = Connect.files.count > Connect.bot.latestFilesLimit ? Connect.files.count - Connect.bot.latestFilesLimit : 0
            for f in Connect.files.dropLast(drop) {
                if let path = (f.path as NSString).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) {
                    self.send(reply: "- \(f.name!): wired:///\(path)")
                }
                
            }
            Connect.files.removeAll()
        }
    }
    
    func connectionDidReceiveError(connection: Connection, message: P7Message) {
        if Connect.connection != nil && Connect.connection.isConnected() {
            
        }
    }
    
    
    
    
    // MARK: -
    
    func bot(_ bot: Bot, wantToSend message: String) {
        if Connect.connection != nil && Connect.connection.isConnected() {
            self.send(reply: message)
        }
    }
    
    
    func bot(_ bot:Bot, wantToSubscribeTo directory:String) {
        if Connect.connection != nil && Connect.connection.isConnected() {
            let message = P7Message(withName: "wired.file.subscribe_directory", spec: Connect.spec)
            message.addParameter(field: "wired.file.path", value: directory)
            _ = Connect.connection.send(message: message)
        }
    }
    
    
    func bot(_ bot:Bot, wantToList directory:String) {
        self.list(path: directory)
    }
    
    
    // MARK: -
    
    private func send(reply text:String, withSleep:Bool = false) {
        if Connect.connection != nil && Connect.connection.isConnected() {
            let sec = Int.random(in: 2..<6)
            
            if withSleep {
                sleep(UInt32(sec))
            }
            let message = P7Message(withName: "wired.chat.send_say", spec: Connect.spec)
            message.addParameter(field: "wired.chat.say", value: text)
            message.addParameter(field: "wired.chat.id", value: UInt32(1))
            _ = Connect.connection.send(message: message)
        }
    }
    
    private func list(path:String) {
        let message = P7Message(withName: "wired.file.list_directory", spec: Connect.spec)
        message.addParameter(field: "wired.file.path", value: path)
        _ = Connect.connection.send(message: message)
    }
    
    
    // MARK: -
    
    private func appDirecoryURL() -> URL {
        var homeDirURL = FileManager.default.homeDirectoryForCurrentUser
        homeDirURL.appendPathComponent(".wirebot")
        
        if !FileManager.default.fileExists(atPath: homeDirURL.path) {
            do {
                try FileManager.default.createDirectory(at: homeDirURL, withIntermediateDirectories: true, attributes: nil)
            } catch let e {
                print(e)
            }
        }
        
        return homeDirURL
    }
    
    private var specPath:String? {
        get {
            return appDirecoryURL().appendingPathComponent("wired.xml").path
        }
    }
    
    private var dataPath:String? {
        get {
            return appDirecoryURL().appendingPathComponent("chatterbot-corpus/chatterbot_corpus/data").path
        }
    }
    
    private var defaultConfigPath:String? {
        get {
            return appDirecoryURL().appendingPathComponent("wirebot.json").path
        }
    }
    
    private var defaultConfig:[String:Any] {
        [
          "rss_feeds": [
            
          ],
          "watched_directories": [
            
          ],
          "icon": "/path/to/icon",
          "nick": "Wiredbot",
          "status": "NLP Powered",
          
          "primaryLanguage": "english",
          "fuzzyness": 0.7,

          "minInactvityTime": 120.0,
          "maxInactvityTime": 480.0,

          "checkFeedTime": 900,
          "checkFeedItemLimit": 3,
          
          "latestFilesLimit": 5,
        ]
    }
    
    
    private func writeJSON(_ dict:[String:Any], to path:String) {
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: self.defaultConfig, options: [JSONSerialization.WritingOptions.withoutEscapingSlashes, JSONSerialization.WritingOptions.prettyPrinted])

            try jsonData.write(to: URL(fileURLWithPath: path))
        } catch let e {
            Logger.error(e.localizedDescription)
        }
    }
    
    
    private func loadJSON(from path:String) -> [String:Any]? {
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            return try JSONSerialization.jsonObject(with: data) as? [String:Any]
            
        } catch let e {
            Logger.error(e.localizedDescription)
        }
        
        return nil
    }
    
    
    private func initWirebot() {
        // check and load local config file (~/.wirebot/config.json)
        var configPath = self.defaultConfigPath
        
        if let c = self.config_path {
            configPath = c
        }
        
        if let path = configPath {
            if !FileManager.default.fileExists(atPath: path) {
                self.writeJSON(self.defaultConfig, to: path)
                Connect.config = self.defaultConfig
            }
            else {
                if let c = self.loadJSON(from: path) {
                    Connect.config = c
                }
            }
        }
        
        // download and install spec
        Logger.info("Download and install Wired 2.0 specification...")
        
        if let path = self.specPath {
            let destURL = URL(fileURLWithPath: path)
            
            if !FileManager.default.fileExists(atPath: path) {
                if let specURL = URL(string: "https://wired.read-write.fr/wired.xml") {
                    do {
                        let wiredSpec = try String(contentsOf: specURL)
                        
                        try wiredSpec.write(to: destURL, atomically: true, encoding: .utf8)
                        
                    } catch let e {
                        print(e)
                    }
                }
            }
        }
        
        
        // download and install corpus
        Logger.info("Download and install ChaterBot Corpus...")

        if !FileManager.default.fileExists(atPath: Process.gitExecURL.path) {
            Logger.fatal("Git not found at \(Process.gitExecURL.path), required.")
            Self.exit(withError: nil)
        }
         
        let repoDest = appDirecoryURL().appendingPathComponent("chatterbot-corpus")
        
        if !FileManager.default.fileExists(atPath: repoDest.path) {
            if let repoURL = URL(string: "https://github.com/gunthercox/chatterbot-corpus.git") {
                try! Process().clone(repo: repoURL, to: repoDest)
            }
        }
    }
    
    
    // MARK: -
    
    private static func indexOf(userID:UInt32) -> Int? {
        var index = 0
        
        for u in Connect.users {
            if u.userID == userID {
                return index
            }
            index += 1
        }
        
        return nil
    }
    
    private static func user(withID userID:UInt32) -> UserInfo? {
        for u in Connect.users {
            if u.userID == userID {
                return u
            }
        }
        return nil
    }
}





// MARK: -


struct Wirebot: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Wired 2.0 chatbot powered by NLP!",
        subcommands: [Connect.self]
    )

    init() { }
}

Wirebot.main()
