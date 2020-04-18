//
//  NLPMessage.swift
//  wirebot
//
//  Created by Rafael Warnault on 12/04/2020.
//  Copyright © 2020 Read-Write. All rights reserved.
//

import Foundation
import WiredSwift
import NaturalLanguage
import CoreML
import CreateML


var enQuestionPrefixes:[String] = ["how", "what", "who", "where", "when", "which", "why", "when", "whose", "do", "did", "does"]

public class NLPMessage: CustomStringConvertible {
    let tagger = NLTagger(tagSchemes: [.sentimentScore, .lemma, .nameTypeOrLexicalClass])
    
    var nickName:String!
    var messageText:String!
    var symbolText:String!
    var date:Date!
    
    var tokens:             [String] = []
    var lemmas:             [String] = []
    var nameTypes:          [String] = []
    var personalNames:      [String] = []
    var organizationNames:  [String] = []
    var placeNames:         [String] = []

    var tokenNeighbors:     [String:[String:Double]] = [:]
    
    var lang:String!
    var sentimentScore:Double!
    
    var isPositive:Bool {
        return self.sentimentScore > 0
    }
    
    var isInterrogative:Bool {
        get {
            if messageText.last == "?" {
                return true
            }
            
            for p in enQuestionPrefixes {
                if messageText.starts(with: p) {
                    return true
                }
            }
            
            return false
        }
    }
    
    var isInterjective:Bool {
        get {
            for t in self.nameTypes {
                if t == "Interjection" {
                    return true
                }
            }
            
            return false
        }
    }
    
    public init(withMessage message:String, byNick nick:String) {
        self.messageText    = message
        self.nickName       = nick
        self.date           = Date()
        
        self.tagger.string  = self.messageText
        
        // language
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(self.messageText)
        if let string = recognizer.dominantLanguage?.rawValue {
            self.lang = string
        }
        
        // tokenizer
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = message
        tokenizer.enumerateTokens(in: message.startIndex..<message.endIndex) { tokenRange, _ in
            self.tokens.append(String(message[tokenRange]))
            return true
        }
        
        
        // word embeddings
        if recognizer.dominantLanguage != nil {
            let embedding = NLEmbedding.wordEmbedding(for: recognizer.dominantLanguage!)
            for t in self.tokens {
                var d:[String:Double] = [:]
                embedding?.enumerateNeighbors(for: t.lowercased(), maximumCount: 5) { (string, distance) -> Bool in
                    d[string] = distance
                    return true
                }
                tokenNeighbors[t] = d
            }
        }
        
        let range = self.messageText.startIndex..<self.messageText.utf16.endIndex
        let options: NLTagger.Options = [.omitPunctuation, .omitWhitespace, .joinNames]
        
        // LEMMAS
        tagger.enumerateTags(in: range, unit: .word, scheme: .lemma) { (tag, outRange) -> Bool in
            if let lemma = tag?.rawValue {
                self.lemmas.append(lemma)
            }
            return true
        }
        
        //COMMON NAMES
        tagger.enumerateTags(in: range, unit: .word, scheme: .nameTypeOrLexicalClass, options: options) { (tag, outRange) -> Bool in
            if let tag = tag {
                if tag.rawValue == NLTag.personalName.rawValue {
                    let name = (self.messageText as NSString).substring(with: NSRange(outRange, in: self.messageText))
                    self.personalNames.append(name)
                } else if tag.rawValue == NLTag.organizationName.rawValue {
                    let name = (self.messageText as NSString).substring(with: NSRange(outRange, in: self.messageText))
                    self.organizationNames.append(name)
                    
                } else if tag.rawValue == NLTag.placeName.rawValue {
                    let name = (self.messageText as NSString).substring(with: NSRange(outRange, in: self.messageText))
                    self.placeNames.append(name)
                    
                } else {
                    self.nameTypes.append(tag.rawValue)
                }
            }
            return true
        }
        
        // NAME TYPES AND CLASSES
        tagger.enumerateTags(in: range, unit: .word, scheme: .nameTypeOrLexicalClass) { (tag, outRange) -> Bool in
            if let nameType = tag?.rawValue {
                self.nameTypes.append(nameType)
            }
            return true
        }
        
        // SENTIMENT SCORE
        if let sentiment = tagger.tag(at: self.messageText.startIndex, unit: .paragraph, scheme: .sentimentScore).0,
            let score = Double(sentiment.rawValue) {
            self.sentimentScore = score
        }
        
        self.symbolText = NLPMessage.symbolize(message)
    }
    
    
    
    public static func symbolize(_ string:String) -> String? {
        let options: NLTagger.Options = [.omitPunctuation, .omitWhitespace, .joinNames]
        let tagger = NLTagger(tagSchemes: [.lemma, .nameTypeOrLexicalClass])
        
        tagger.string = string
        
        var range = string.startIndex..<string.utf16.endIndex
        var lemmas:[String] = []
        
        let excludedTags:[NLTag] = [
            .closeParenthesis,
            .closeQuote,
            .conjunction,
            .dash,
            .determiner,
            .interjection,
            .number,
            .openParenthesis,
            .openQuote,
            .paragraphBreak,
            .preposition,
            .classifier,
            .particle,
            .wordJoiner]
        
        
        tagger.enumerateTags(in: range, unit: .word, scheme: .nameTypeOrLexicalClass, options: options) { (tag, outRange) -> Bool in
            if let tag = tag {
                if !excludedTags.contains(tag) {
                    let name = (string as NSString).substring(with: NSRange(outRange, in: string))
                    lemmas.append(name)
                }
            }
            return true
        }
        
        let newString = lemmas.joined(separator: " ")
        range = newString.startIndex..<newString.utf16.endIndex
        tagger.string = newString
        lemmas = []
        
        tagger.enumerateTags(in: range, unit: .word, scheme: .lemma, options: options) { (tag, outRange) -> Bool in
            if let tag = tag {
                if !excludedTags.contains(tag) {
                    let name = (newString as NSString).substring(with: NSRange(outRange, in: newString))
                    lemmas.append(name)
                }
            }
            return true
        }
        
        return lemmas.joined(separator: " ").lowercased()
    }
    
    
    
    public var description: String {
        return """
MESSAGE ###################
Nick:\t\(self.nickName!)
Text:\t\(self.messageText!)

Language: \(self.lang ?? "unknow")
Sentiment score: \(self.sentimentScore != nil ? self.sentimentScore! : 0)

Tokens:
            
    \(self.tokens)
        
Neighbors:
        
    \(self.tokenNeighbors)
        
Lemmas:
    
    \(self.lemmas.joined(separator: ", "))

Name Types:

    \(self.nameTypes.joined(separator: ", "))
  
Name Types:

    \(self.personalNames.joined(separator: ", "))
   
Personal Names:
    
    \(self.personalNames.joined(separator: ", "))

Organization Names:

    \(self.organizationNames.joined(separator: ", "))
  
Place Names:

    \(self.placeNames.joined(separator: ", "))
        
END     ###################
\n
"""
    }
}

