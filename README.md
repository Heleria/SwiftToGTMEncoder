# SwiftToGTMEncoder

## What it does

This tool converts Swift constants of the following types into GTM-supported JSON-constants (GTM doesn't support JSON-arrays which was the main reason I made this tool):
 - Arrays (can recursively contain anything on this list except CGSize)
 - Dictionaries (can recursively contain anything on this list except CGSize)
 - CGFloats
 - CGRects
 - CGSize (not supported inside arrays or dictionaries)
 - UIColor
 - All primitives

This tool is meant to convert these constants into JSON-values that can easily be decoded into Swift-values by https://github.com/Heleria/GTMReader. 

## Installation

Download 'main.swift'

## How to use

In 'main.swift', replace the content of 'replaceRealInput()' with 'input += <ALL OF THE CONSTANTS YOU WANT CONVERTED ENCLOSED BY QUOTATION MARKS SO THAT EVERYTHING IS ONE BIG STRING. JUST LOOK AT WHAT IS THERE FROM BEFORE AND YOU'LL UNDERSTAND>' and hit run. Copy paste the output into JSON-tags and copy paste that again into a Value Collection on the Google Tag Manager webpage.

## Note
This was a tool that I made as quickly as possible to convert a lot of constants in my code. Thus it is very poorly coded and sometimes makes some mistakes (look at the comments in 'main.swift' to see the specifics). I simply uploaded this because I could not find anyone else that had done anything similiar in advance and was hoping that this could at least be better than converting all values manually.

Anyone that wants to improve the code are welcome to do so!

## Author

Heleria, Jacob.R.Developer@gmail.com

## License

SwiftToGTMEncoder is available under the MIT license. See the LICENSE file for more info.
