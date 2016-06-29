//  Remake of old project by Jacob Henning Rothschild from 27/03/2016.
//
//  main.swift
//  SwiftToGTMEncoder
//
//  Created by Jacob Henning Rothschild on 30/06/2016.
//  Copyright © 2016 Heleria. All rights reserved.
//

import Foundation

/// The type of value we are currently working with
enum ValueType : String {
    case UNKNOWN
    case STRING = "STRING"
    case INT = "INT"
    case DOUBLE = "DOUBLE"
    case FLOAT = "FLOAT"
    case COLOR = "COLOR"
    case SIZE = "SIZE"
    case ARRAY = "ARRAY"
    case DICTIONARY = "DICTIONARY"
}

// WARNING: Doesn't support non-primitive keys. All keys are stored as strings
// WARNING: Prints an extra line with just a key whenever enters a collection type from a dictionary, or leaves a dictionary
// WARNING: Usually messes slightly up key after a constructor in dictionaries
// WARNING: If first value of input is a dictionary, doesn't output type of first value
// WARNING: Sometimes skips absolutely last value of input
// NOTE: Would have been a way better structure to first read all input into variables/collections and then print, instead of trying to print directly; too late for that now


/// - Parameter index: The index if the collection is an array
/// - Parameter keys: The keys if the collection is a dictionary
/// - Parameter paramIndex: The index within a constructor
struct Collection {
    var index: Int?, keys: [String], paramIndex: Int?
    init() {index = nil; keys = []; paramIndex = nil}
    init(paramIndex: Int) {self.init(); self.paramIndex = paramIndex}
}

/// The exact strings that indicate certain kinds of ValueTypes
private let VALUE_TYPES: [String : ValueType] = ["CGFloat" : .FLOAT, "CFTimeInterval" : .FLOAT, "UIColor" : .COLOR, "CGSizeMake" : .SIZE]

/// The relationship between all the UIColor.CONSTANTs and how they're represented in GTM-JSON
private let COLOR_CONSTANTS = ["groupTableViewBackgroundColor(" : "BACKGROUND_VIEW_TABLE_GROUP", "darkTextColor(" : "TEXT_DARK", "lightTextColor(" : "TEXT_LIGHT", "blackColor(" : "BLACK", "darkGrayColor(" : "GRAY_DARK", "grayColor(" : "GRAY", "lightGrayColor(" : "GRAY_LIGHT", "whiteColor(" : "WHITE", "clearColor(" : "CLEAR", "brownColor(" : "BROWN", "purpleColor(" : "PURPLE", "magentaColor(" : "MAGENTA", "yellowColor(" : "YELLOW", "cyanColor(" : "CYAN", "blueColor(" : "BLUE", "greenColor(" : "GREEN", "orangeColor(" : "ORANGE", "redColor(" : "RED"]

/// The swift-code that we're converting
var input = ""
/// Each index represents one line of output. This way we can insert line indicating array length before array elements, once we've read the whole thing and knows it's length
var output = [String]()
/// The name of the constant we're currently converting. If the constant is a variable this will only be printed once, while if it is an array this will be the key prefix for each index of the array
var key = ""
/// When true, reading the constants name
var readingKey = true
/// When true, skipping the characters between the constants name and it's value(s)
var skipping = false
/// When true, will skip the next word. This is relevant when the source code contains explicit type declarations, seeing how we will not be doing anything equivalent in GTM
var skippingWord = false
/// An array of arrays, dictionaries and constructors within each other
var collections = [Collection]()
/// The current char in the input.characters iterator
var char: Character!
/// We don't always know beforehand what type of variable we're reading. Some variable types are stored differently, and we must thus save the whole word and process it's type before storing
var word = ""
/// The type of value we are reading
var valueType = ValueType.UNKNOWN
/// Indicates we'll either be reading a method that returns a constant, or a constant
var callingConstants = false
/// Indicates whether we're currently within String-brackets ""
var inStringBrackets = false
/// Indicates whether we'll avoid calling addNewVarLine() on the next ","
var skippingComma = false
/// Used by findValueType() to know whether we just discovered that we're in the middle of reading a double and should thus set valueType = .DOUBLE and wait with calling outputValueType()
var handlingDot = false
/// Used when printing all the keys for a dictionary, as a suffix to the JSON-keys that the dictionary-keys are stored under
var keyIndex = -2

/// Converts from swift to GTM-JSON
func convert(input: String) -> [String] {
    // Loops through all characters of the input
    for curChar in input.characters {
        char = curChar
        testIfStringBrackets()
        if inStringBrackets {
            handleSomewhatNormalChar()
        } else if char == "=" {
            handleEqualSign()
        } else if skippingWord {
            // We are skipping until "=" is reached, so we do nothing
        } else if char == "[" {
            handleCollectionOpening()
        } else if char == "]" {
            handleCollectionClosing()
        } else if char == "(" && !callingConstants {
            handleConstructorOpening()
        } else if char == ")" && !callingConstants {
            handleConstructorClosing()
        } else if char == ")" {
            handleConstantFinished()
        } else if char == "," {
            handleComma()
        } else if char == "." && !inConstructor() {
            handleDot()
        } else if char == " " {
            handleFillerChars()
        } else if char == ":" {
            handleColon()
        } else if !readingKey && char == "_" {
            // We do absolutetly nothing
        } else {
            handleSomewhatNormalChar()
        }
    }
    // In case input ends with a primitive markWordEnd() won't have been called for this before
    finish()
    fixMistakes()
    return output
}

/// - Returns: Whether we're directly modifying values in a constructor, 'collections.last?.paramIndex != nil'
func inConstructor() -> Bool {
    return collections.last?.paramIndex != nil
}

/// Calls markWordEnd() if !word.isEmpty
func markWordEndIfNotEmpty() {
    if !word.isEmpty {
        markWordEnd()
    }
}

/// Calls markWordEnd() if we we're reading a value that still hasn't been outputted (happens for primitives)
func finish() {
    if valueType != .UNKNOWN && !word.isEmpty{
        markWordEnd()
    }
}

/// Sets inStringBrackets = !inStringBrackets if this letter is (") and the last letter was not "\"
func testIfStringBrackets() {
    if char == "\"" && (word.characters.count == 0 || word[word.endIndex.advancedBy(-1)] != "\\") {
        inStringBrackets = !inStringBrackets
        if valueType == .UNKNOWN {
            valueType = .STRING
        }
    }
}

/// This char indicates the next thing we'll be reading won't be a key, but rather a value
func handleEqualSign() {
    readingKey = false
    // skippingWord is only ever relevant for the potential one-word explicit type declaration before this equal sign. Thus when this char is reached, skippingWord should no longer be true
    skippingWord = false
}

/// This char indicates we're moving into an array. Thus we must update arrayDepth
func handleCollectionOpening() {
    if !collections.isEmpty && !knowsCollectionType() {
        // We don't support arrays or dictionaries as keys, so what we used to have must be an array (NOTE: this modifies the parent array of the array we're about to add)
        collections[collections.count - 1].index = 0
    }
    collections.append(Collection())
}

/// This char indicates we're moving out of an array. Thus we must update arrayDepth
func handleCollectionClosing() {
    if !word.isEmpty {
        // We add the last value within the brackets, just like it would have been added when the next value or key was read, had more values existed
        setCollectionIndexIfNecessary()
        markWordEnd()
    }
    writeCollectionOverviewAndRemove()
    // We are now finally finished printing all values for index or key, so unlike normally we don't want to do this on the next ","
    if knowsCollectionType() {
        skippingComma = true
    }
}

/// Prints the index or keys of the collection we're removing before removing it
func writeCollectionOverviewAndRemove() {
    let removedCollection = collections.removeLast()
    writeIndexOrKeysForRemovedCollection(removedCollection)
}

/// Prints the index or keys of the collection we're removing
func writeIndexOrKeysForRemovedCollection(collection: Collection) {
    if let index = collection.index {
        writeIndexAndTypeForRemovedArray(index)
    } else {
        writeKeysAndTypeForRemovedDictionary(collection.keys)
    }
}

/// Writes the array.count and .ARRAY type for the array we just finished printing
func writeIndexAndTypeForRemovedArray(index: Int) {
    addNewVarLine()
    writeToOutput("\(index + 1)")
    addNewVarLine(true)
    writeToOutput("\"\(ValueType.ARRAY)\"")
}

/// Writes the dictionary.keys and .DICTIONARY type for the dictionary we just finished printing
func writeKeysAndTypeForRemovedDictionary(keys: [String]) {
    writeKeys(keys)
    addNewVarLine(true)
    writeToOutput("\"\(ValueType.DICTIONARY)\"")
}

/// Writes all keys under the key "\(origianlKey)\(:KEYS): "
func writeKeys(keys: [String]) {
    keyIndex = -1
    addNewVarLine()
    writeToOutput("\(keys.count)")
    for index in 0 ..< keys.count {
        keyIndex = index
        writeKey(keys[index])
    }
    keyIndex = -2
}

/// Writes this key under the key "\(origianlKey)\(:KEYS),\(keyIndex): "
func writeKey(key: String) {
    addNewVarLine()
    writeToOutput("\"\(key)\"")
    addNewVarLine(true)
    writeToOutput("\"\(ValueType.STRING)\"")
}

/// This is called when a "," og "]" is reached. If !collections.isEmpty && !knowsCollectionType() we must set .index to -1, before soon being increased by 1
func setCollectionIndexIfNecessary() {
    if !collections.isEmpty && !knowsCollectionType() {
        collections[collections.count - 1].index = 0
        addNewVarLine()
    }
}

/// Handles the "(" which indicates we're moving into a constructor. Thus we must update varDepth
func handleConstructorOpening() {
    collections.append(Collection(paramIndex: 0))
    markWordEnd()
    possiblyWriteBracket()
}

/// All values with constructors except floats are outputted as strings, so if valueType != .FLOAT, writeToOutput("\"")
func possiblyWriteBracket() {
    if valueType != .FLOAT {
        writeToOutput("\"")
    }
}

/// Handles the ")" which indicates that we're moving out of a constructor. Thus we must update varDepth
func handleConstructorClosing() {
    markWordEnd()
    possiblyWriteBracket()
    outputValueType()
    collections.removeLast()
    skipping = true
    // Setting valueType here is necessary if this is last value, so that we don't risk trying to convert an empty string when we call markWordEnd() at end of convert()
    valueType = ValueType.UNKNOWN
}

/// Handles the ")" when we're reading a constant. This indicates that we're finished reading this constant
func handleConstantFinished() {
    outputWord()
    // This is necessary so that finish() doesn't try outputting an empty variable
    valueType = ValueType.UNKNOWN
}

/// This char indicates we are finished reading this value and will now move on to the next value of this level/dimension
func handleComma() {
    outputWord()
    if !inConstructor() {
        skipping = true
    }
    increaseIndexOrChangeVariable()
    handleFillerChars()
}

/// Does everything that is necessary in order to safely print a word in any situation
func outputWord() {
    setCollectionIndexIfNecessary()
    // It is important to call markWordEndIfNotEmpty() this early so that "\(key)|type" contains correct key
    markWordEndIfNotEmpty()
    if !inConstructor() {
        valueType = ValueType.UNKNOWN
    }
}

/// Increases the last arrayIndex if it exists and increases the last paramIndex if it exists. If neither is the case, notifies that we'll next be reading a key
func increaseIndexOrChangeVariable() {
    if possiblyIncreaseLastArrayIndex() & possiblyIncreaseLastParamIndex() == 1 {
        notifyOfImminentKeyRead()
    }
}

/// Increases the last collections.index if it exists
/// - Returns: collections.isEmpty
func possiblyIncreaseLastArrayIndex() -> Int {
    if collections.last?.index != nil {
        collections[collections.count - 1].index! += 1
    }
    return collections.isEmpty ? 1 : 0
}

/// Increases the last collections.paramIndex if it exists
/// - Returns: collections.isEmpty
func possiblyIncreaseLastParamIndex() -> Int {
    if collections.last?.paramIndex != nil {
        collections[collections.count - 1].paramIndex! += 1
    }
    return collections.isEmpty ? 1 : 0
}

/// The next thing we'll be reading is the name of a variable (NOTE: Not a key inside of a dictionary)
func notifyOfImminentKeyRead() {
    key = ""
    readingKey = true
}

/// These are just filler characters for viewability, serving us no purpose here. Thus they should not be read
func handleFillerChars() {
    if readingKey {
        skipping = true
    }
}

/// This char indicates we're reading a constant of the type we found with the last word, if that word was not a string or number
func handleDot() {
    if valueType == .STRING {
        // Part of a number or string, so we're just adding it to the word instead of calling constants
        writeToWord(char)
    } else {
        handlingDot = true
        markWordEnd()
        callingConstants = true
    }
}

/// - Returns: Whether either .index or .keys.last of collections.last is known
func knowsCollectionType() -> Bool {
    return !collections.isEmpty && (collections.last?.index != nil || !collections.last!.keys.isEmpty || inConstructor())
}

/// We are finished reading a word. We must now figure out what kind of value we just read, and add it
func markWordEnd() {
    if valueType == .UNKNOWN {
        valueType = VALUE_TYPES[word] ?? actOnAndReturnValueTypeString()
    } else {
        actOnRecordedValueType()
    }
    if valueType != .DOUBLE || !readingDictionaryKey() {
        resetWord()
    }
}

/// Returns ValueType.STRING after first calling actOnRecordedValueType() (where valueType = .UNKNOWN)
func actOnAndReturnValueTypeString() -> ValueType {
    valueType = findValueType()
    actOnRecordedValueType()
    return valueType
}

/// - Returns: The ValueType of the word we're reading / just read
func findValueType() -> ValueType {
    return handlingDot ? addDotAndReturnDoubleType() : .INT
}

/// Calls 'word += "."' to add the iconic "." to the double we're outputting, and return .DOUBLE because that is what we're outputting
func addDotAndReturnDoubleType() -> ValueType {
    word += "."
    return .DOUBLE
}

/// Calls the correct output processing function for this ValueType
func actOnRecordedValueType() {
    if valueType == .DOUBLE && readingDictionaryKey() {
        return
    }
    switch valueType {
    case .COLOR: outputColor()
    case .SIZE: outputSize()
    case .FLOAT: outputFloat()
    default:
        writeToOutput(word)
    }
    // Must be placed after outputting value, because the key for the value is already written to output, so formatting won't work otherwise. Should not be called if handlingDot, because then we'll still be in the middle of converting a value. if inConstructor(), we'll be calling outputValueType() when the constructor is closing, instead of in the middle of it
    if !handlingDot && !inConstructor() {
        outputValueType()
    }
}

/// - Returns: Whether we're currently reading a dictionary-key
func readingDictionaryKey() -> Bool {
    return !collections.isEmpty && collections.last?.index == nil && collections.last?.paramIndex == nil && (output.isEmpty || output.last!.substringFromIndex(output.last!.startIndex.advancedBy(output.last!.characters.count - 8)) != "|type\": ")
}

/// Adds a new line with the same key as the value we just added, but the value is a String defining its type
func outputValueType() {
    addNewVarLine(true)
    writeToOutput("\"\(valueType.rawValue)\"")
}

/// Writes piece by piece a UIColor to output
func outputColor() {
    if callingConstants {
        outputColorConstant()
    } else if word.characters.count > 1 && word.substringToIndex(word.startIndex.advancedBy(2)) == "0x"{
        outputColorCustomHex()
    } else {
        outputColorCustomRGBA()
    }
}

/// We are calling one of the UIColor constants
func outputColorConstant() {
    writeToOutput("\"\(COLOR_CONSTANTS[word]!)\"")
}

/// We are calling the UIColor(hex) constructor
func outputColorCustomHex() {
    // We replace "0x" with "#" and the hex is converted to GTM-JSON format
    writeToOutput(word.stringByReplacingOccurrencesOfString("0x", withString: "#"))
}

/// We are calling the UIColor(red:, green:, blue:, alpha:) constructor
func outputColorCustomRGBA() {
    if word == "red" {
        // We start the string for this color value
        writeToOutput("#")
    } else if word == "green" || word == "blue" || word == "alpha" {
        // We do nothing
    } else {
        // We write the hex-representation for one of the rgb(a) values
        writeToOutput(String(format:"%2X", Int(round(Double(word)! * 255))))
    }
}

/// Writes piece by piece a CGSizeMake to output
func outputSize() {
    writeToOutput("\(word)" + (collections.last?.paramIndex == 0 ? "," : ""))
}

/// Just prints the float, but if constructor is left empty print "0" instead of ""
func outputFloat() {
    writeToOutput(word.isEmpty ? "0" : word)
}

/// Clears the word string, and defaults all values exclusive to this word
func resetWord() {
    word.removeAll()
    callingConstants = false
    handlingDot = false
}

/// A colon can have different meanings in different contexts
func handleColon() {
    if collections.isEmpty && readingKey {
        skipping = true
        skippingWord = true
    } else if inConstructor() {
        markWordEnd()
    } else {
        handleDictionaryColon()
    }
}

/// When a colon is read within square brackets that means the last word was the key for the next word which will be the value
func handleDictionaryColon() {
    // Adds the key to this dictionarys keys. If first char is (") the last will be the same, and we want neither
    collections[collections.count - 1].keys.append(word.characters[word.startIndex] == "\"" ? word.substringWithRange(word.startIndex.advancedBy(1) ..< word.endIndex.advancedBy(-1)) : word)
    resetWord()
    addNewVarLine()
    valueType = .UNKNOWN
    //    skippingComma = true
}

/// Handles all chars that in the current context doesn't warrant any specific action other than being added to the current word
func handleSomewhatNormalChar() {
    if readingKey {
        // Add char to key
        char.writeTo(&key)
    } else {
        startOrWriteToVar()
    }
    skipping = false
}

/// Either adds a new line of output or writes to the current word
func startOrWriteToVar() {
    if skipping && !skippingComma && (collections.isEmpty || knowsCollectionType()) {
        if collections.isEmpty {
            markWordEndIfNotEmpty()
        }
        if collections.isEmpty || collections.last!.keys.isEmpty {
            addNewVarLine()
        }
        markWordEndIfNotEmpty()
        writeToWord(char)
        valueType = .UNKNOWN
    } else {
        // Add char to current word
        writeToWord(char)
    }
    skippingComma = false
}

/// Adds a comma at the end of the current line, and adds a new line with a key
/// - Parameter writingType: Indicates whether we're currently writing what type of value exists behind a key (marked by the "|type" suffix)
func addNewVarLine(writingType: Bool = false) {
    // Add the comma at the end of the current line
    writeToOutput(",")
    // Add a new part with the key-part of the line
    createAndKeyFillNewLine(writingType)
}

/// Adds a new line to output that starts with the current key (inclusive collection suffix)
func createAndKeyFillNewLine(writingType: Bool = false) {
    output.append(makeJSONKey("\(key)\(convertToCollectionSuffix(collections))", writingType: writingType))
}

/// Converts 'key' with a possible "|type" suffix if writingType == true into the key part of a JSON object
func makeJSONKey(key: String, writingType: Bool) -> String {
    return "\"\(key)\(keyIndex > -2 ? ":KEYS\(keyIndex > -1 ? ",\(keyIndex)" : "")" : "")\(writingType ? "|type" : "")\": "
}

/// - parameter collections: The index or key in the different dimensions of arrays and dictionaries we're currently in
/// - returns: "_collections[0].index__collections[1].key__collections[2].index..."
func convertToCollectionSuffix(collections: [Collection]) -> String {
    var output = ""
    for collection in collections {
        if let index = collection.index {
            output += ",\(index)"
        } else if collection.paramIndex == nil {
            output += ";\(collection.keys.last!)"
        }
    }
    return output
}

/// Adds char to the end of variable word
func writeToWord(char: Character) {
    char.writeTo(&word)
}

/// Adds char to the end of last line of output
func writeToOutput(word: String) {
    if !output.isEmpty {
        word.writeTo(&output[output.count - 1])
    }
}

/// Fixes some of the more obvious mistakes the program has made thus far. This function shouldn't be necessary, but it is
func fixMistakes() {
    // Removes lines containing "\": ,", because they're results of bugs, and shouldn't exist
    for var index = 0; index < output.count; index += 1 {
        if output[index].containsString("\": ,") {
            output.removeAtIndex(index)
            index -= 1
        }
    }
}

/// Prints the output of our conversion
func printConverted(input: [String]) {
    for out in input {
        print(out)
    }
}

func testPrimitives() {input += "TEST_INT = 5, TEST_DOUBLE = 1.2, RANDOM_INT = 7, RANDOM_DOUBLE = 5.3"}
func testComplex() {input += "TEST_INT = 5, TEST_DOUBLE = 1.2, TEST_COLOR = UIColor.whiteColor(), TEST_FLOAT = CGFloat(10), TEST_STRING = \"abcdefg\", TEST_SIZE = CGSizeMake(80, 80), RANDOM_COLOR = UIColor(red: 0.25, green: 0.25, blue: 0.5, alpha: 0.9), HEX_COLOR = UIColor(0x12345678)"}
func test1dArrayWithPrimitives() {input += "TRACKS = [\"test0\", \"test1\", \"test2\", \"test3\", \"test4\", \"test5\", \"test6\"]"}
func test1dArrayWithComplex() {input += "array = [UIColor.whiteColor(), \"randomTest\", UIColor(red: 0.25, green: 0.25, blue: 0.5, alpha: 0.9), CGFloat(10), CGSizeMake(80, 80), UIColor.redColor(), UIColor(0x12345678)]"}
func testArrayPlusVariables() {input += "TEST_TRACKS = [[\"testa\", \"testb\"], [\"testc\", \"testd\", \"teste\", \"testf\", \"testg\"]], RAND_COLOR = UIColor.whiteColor(), TEST_MAX = 10"} // ERROR: Doesn't call addNewVarLine() after reading key of value after leaving last level of array, so value gets drawn on previous line (but the value is correct)
func test2dArrayWithPrimitives() {input += "TRACKS = [[\"test0\", \"test1\"], [\"test2\", \"test3\", \"test4\", \"test5\", \"test6\"]]"}
func testDictionary() {input += "DICTION = [\"0.25\" : 0.5, \"0.10\" : \"0.25\", \"0.12\" : \"0.252\", \"25\" : 5, \"10\" : \"259\", \"abc\" : [9, 8, 7, 6, 5], \"12\" : \"252\"]"}
func testDictionaryInArray() {input += "ARRAY_WITH_DICTIONARY = [[\"0.25\" : 0.5, \"0.10\" : \"0.25\", \"0.12\" : \"0.252\", \"25\" : 5, \"10\" : \"259\", \"abc\" : [9, 8, 7, 6, 5], \"12\" : \"252\"], [10 : \"TEST\", \"abc\" : \"test2\"]]"}
func testDictionaryInDictionary() {input += "DICTIONARY_WITH_DICTIONARY = [\"first\" : [\"0.25\" : 0.5, \"0.10\" : \"0.25\", \"0.12\" : \"0.252\", \"25\" : 5, \"10\" : \"259\", \"abc\" : [9, 8, 7, 6, 5], \"12\" : \"252\"], 10 : [10 : \"TEST\", \"abc\" : \"test2\"]]"}
func testDictionaryWithArrayWithDictionary() {input += "BUNDLE_PRODUCTS = [\"first\" : [\"f.first\", \"f.second\", \"f.third\"], \"f.fourth\" : [\"cc.st\", \"cc.adsdfs\", \"cc.sec_sdfaall\", [10, [\"final\" : UIColor.redColor(), 200: UIColor(red: 0.25, green: 0.25, blue: 0.5, alpha: 0.9), 0.25 : CGSizeMake(100, 250), 5.678 : CGFloat(0.5)]]]]"}

/// The actual code that we want converted for Climb Crusher
func setRealInput() {input += "GLOBAL_TAG = \"Global.\", BACKGROUND_COLOR = UIColor.whiteColor(), GAME_BACKGROUND_COLOR = UIColor.whiteColor(), CELL_BACKGROUND_COLOR = UIColor.clearColor(), TRACK_SUFFIX_LENGTH = 1, MAX_S_COUNT = 50, DEFAULT_SECTION_COUNT = 2, L_COUNT = 5, CELL_B_TEXT_COLOR = UIColor(red: 0.25, green: 0.25, blue: 0.5, alpha: 0.9), CELL_B_FONT_NAME = \"Baskerville-Bold\", CELL_B_FONT_SIZE : CGFloat = 40, MORE_BUTTON_TEXT = \"+\", CELL_BUTTON_SIZE = CGSizeMake(80, 80), AUDIO_MANAGER_TAG = \"AudioManager.\", MASTER_VOLUME: Float = 0.10, LOBBY_VOLUME: Float = 0.5, TRACKS = [[\"theelevatorbossanova\", \"bensound_thelounge\"], [\"go_cart_0\", \"go_cart_1\", \"ouroboros\", \"the_arcade_0\", \"the_arcade_1\"]], NAVIGATION_ITEMS_MANAGER_TAG = \"NavigationItemsManager.\", MAX_SNAPSHOT_RESOLVE_RETRIES = 10, WELCOME_BACK_OFFSET : UInt = 10000, ACHIEVEMENT_ENDLESS_DURATION = [8_000, 10_000, 12_000, 14_000, 16_000], ACHIEVEMENT_LEVELS_COMPLETED = [1, 5, 15, 25, 50], ACHIEVEMENT_SECTION_COMPLETED = [0, 1, 2, 3, 4, 6, 9, 14], NAME_CLOUD_SAVE = \"cloud_save\", SAVED_GAMES_DESCRIPTION = \"\", ID_PREFIX = \"CgkIo7iwn6gTEAIQ\", ID_ACHIEVEMENT_ONE_FROM_EACH = \"Fg\", ID_ACHIEVEMENT_ENDLESS_DURATION = [\"CQ\", \"Cg\", \"Cw\", \"DA\", \"DQ\"], ID_ACHIEVEMENT_LEVELS_COMPLETED = [\"AQ\", \"Eg\", \"Ew\", \"FA\", \"FQ\"], ID_ACHIEVEMENT_SECTION_COMPLETED = [\"Ag\", \"Aw\", \"EQ\", \"BQ\", \"BA\", \"Bg\", \"Bw\", \"IQ\"], ID_LEADERBOARDS_ENDLESS_DURATION = [\"Dg\", \"Ig\", \"Iw\", \"JA\", \"JQ\", \"Jg\", \"Jw\", \"KA\", \"KQ\", \"Kg\", \"Kw\", \"LA\", \"LQ\", \"Lg\", \"Lw\", \"MA\", \"MQ\", \"Mg\", \"Mw\", \"NA\", \"NQ\", \"Ng\", \"Nw\", \"OA\", \"OQ\", \"Og\", \"Ow\", \"PA\", \"PQ\", \"Pg\", \"Pw\", \"QA\", \"QQ\", \"Qg\", \"Qw\", \"RA\", \"RQ\", \"Rg\", \"Rw\", \"SA\", \"SQ\", \"Sg\", \"Sw\", \"TA\", \"TQ\", \"Tg\", \"Tw\", \"UA\", \"UQ\", \"Ug\"], K_CLIENT_ID = \"663638252579-ps35liq6ae341uo7i8lpud2c0rtq6rf7.apps.googleusercontent.com\", PICK_SECTION_VIEW_CONTROLLER_TAG = \"PickSectionController.\", REUSE_IDENTIFIER = \"section_cell\", IAP_PRODUCT_LOADING_MANAGER_TAG = \"IAPProductLoadingManager.\", ID_PRODUCTS = [\"cc.end\", \"cc.ads\", \"cc.sec_3\", \"cc.sec_10\", \"cc.sec_all\", \"cc.sec_all_end_ads\"], LEVEL_PRODUCTS = [\"cc.sec_3\" : 3, \"cc.sec_10\" : 10, \"cc.sec_all\" : -1], BUNDLE_PRODUCTS = [\"cc.sec_all_end_ads\" : [\"cc.end\", \"cc.ads\", \"cc.sec_all\"]], MORE_VIEW_CONTROLLER_TAG = \"MoreViewController.\", VERTICAL_PADDING = \"-8-\", HORIZONTAL_PADDING = \"-8-\", IAP_B_TEXT_COLOR = UIColor(red: 0, green: 0.478431372549, blue: 1, alpha: 1), PRODUCT_ID_PREFIX = \"cc.\", IAP_B_FONT_NAME = \"Baskerville-Bold\", IAP_B_FONT_SIZE : CGFloat = 20, PICK_LEVEL_VIEW_CONTROLLER_TAG = \"PickLevelController.\", REUSE_IDENTIFIER = \"level_cell\", ENDLESS_BUTTON_TEXT = \"Endless\", LOCKED_BUTTON_TEXT = \"\", ENDLESS_BUTTON_SIZE = CGSizeMake(180, 80), GAME_VIEW_CONTROLLER_TAG = \"GameViewController.\""}

/// What test method we will be calling
enum TestType {case PRIMITIVES; case COMPLEX; case ONE_D_ARRAY_WITH_PRIMITIVES; case ONE_D_ARRAY_WITH_COMPLEX; case TWO_D_ARRAY_WITH_PRIMITIVES; case ARRAY_PLUS_VARIABLES; case DICTIONARY; case DICTIONARY_WITH_ARRAY_WITH_DICTIONARY}

/// Calls one of the test methods before executing
func printForUse() {
    printConverted(convert(input))
    print("\n\n\n")
    resetAll()
}

/// Resets everything
func resetAll() {
    input = ""
    output = [String]()
    key = ""
    readingKey = true
    skipping = false
    skippingWord = false
    collections = [Collection]()
    char = nil
    word = ""
    valueType = ValueType.UNKNOWN
    callingConstants = false
    inStringBrackets = false
    skippingComma = false
    handlingDot = false
}

//printForUse(testPrimitives())
//printForUse(testComplex())
//printForUse(test1dArrayWithPrimitives())
//printForUse(test1dArrayWithComplex())
//printForUse(test2dArrayWithPrimitives())
//printForUse(testArrayPlusVariables())
//printForUse(testDictionary())
//printForUse(testDictionaryInArray())
//printForUse(testDictionaryInDictionary())
//printForUse(testDictionaryWithArrayWithDictionary())
printForUse(setRealInput())