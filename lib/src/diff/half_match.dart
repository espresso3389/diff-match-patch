/// Half Match functions
///
/// Copyright 2011 Google Inc.
/// Copyright 2014 Boris Kaul `<localvoid@gmail.com>`
/// http://github.com/localvoid/diff-match-patch
///
/// Licensed under the Apache License, Version 2.0 (the 'License');
/// you may not use this file except in compliance with the License.
/// You may obtain a copy of the License at
///
///   http://www.apache.org/licenses/LICENSE-2.0
///
/// Unless required by applicable law or agreed to in writing, software
/// distributed under the License is distributed on an 'AS IS' BASIS,
/// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
/// See the License for the specific language governing permissions and
/// limitations under the License.

part of '../diff.dart';

/// Do the two texts share a substring which is at least half the length of
/// the longer text?
///
/// This speedup can produce non-minimal diffs.
///
/// * [text1] is the first string.
/// * [text2] is the second string.
///
/// Returns a five element List of Strings, containing the prefix of [text1],
/// the suffix of [text1], the prefix of [text2], the suffix of [text2] and the
/// common middle.  Or null if there was no match.
List<String>? diffHalfMatch(String text1, String text2) {
  final longText = text1.length > text2.length ? text1 : text2;
  final shortText = text1.length > text2.length ? text2 : text1;
  if (longText.length < 4 || shortText.length * 2 < longText.length) {
    return null; // Pointless.
  }

  // First check if the second quarter is the seed for a half-match.
  final hm1 = _diffHalfMatchI(longText, shortText, ((longText.length + 3) / 4).ceil().toInt());
  // Check again based on the third quarter.
  final hm2 = _diffHalfMatchI(longText, shortText, ((longText.length + 1) / 2).ceil().toInt());
  List<String>? hm;
  if (hm1 == null && hm2 == null) {
    return null;
  } else if (hm2 == null) {
    hm = hm1;
  } else if (hm1 == null) {
    hm = hm2;
  } else {
    // Both matched.  Select the longest.
    hm = hm1[4].length > hm2[4].length ? hm1 : hm2;
  }

  // A half-match was found, sort out the return data.
  if (text1.length > text2.length) {
    return hm;
    //return [hm[0], hm[1], hm[2], hm[3], hm[4]];
  } else {
    return [hm![2], hm[3], hm[0], hm[1], hm[4]];
  }
}

/// Does a substring of [shortText] exist within [longText] such that the
/// substring is at least half the length of [longText]?
///
/// * [longText] is the longer string.
/// * [shortText] is the shorter string.
/// * [i] Start index of quarter length substring within [longText].
///
/// Returns a five element String array, containing the prefix of [longText],
/// the suffix of [longText], the prefix of [shortText], the suffix of
/// [shortText] and the common middle.  Or null if there was no match.
List<String>? _diffHalfMatchI(String longText, String shortText, int i) {
  // Start with a 1/4 length substring at position i as a seed.
  final seed = longText.substring(i, i + (longText.length / 4).floor().toInt());
  var j = -1;
  var bestCommon = '';
  var bestLongTextA = '', bestLongTextB = '';
  var bestShortTextA = '', bestShortTextB = '';
  while ((j = shortText.indexOf(seed, j + 1)) != -1) {
    var prefixLength = calcCommonPrefix(longText.substring(i), shortText.substring(j));
    var suffixLength = calcCommonSuffix(longText.substring(0, i), shortText.substring(0, j));
    if (bestCommon.length < suffixLength + prefixLength) {
      bestCommon =
          '${shortText.substring(j - suffixLength, j)}'
          '${shortText.substring(j, j + prefixLength)}';
      bestLongTextA = longText.substring(0, i - suffixLength);
      bestLongTextB = longText.substring(i + prefixLength);
      bestShortTextA = shortText.substring(0, j - suffixLength);
      bestShortTextB = shortText.substring(j + prefixLength);
    }
  }
  if (bestCommon.length * 2 >= longText.length) {
    return [bestLongTextA, bestLongTextB, bestShortTextA, bestShortTextB, bestCommon];
  } else {
    return null;
  }
}
