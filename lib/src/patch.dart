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

library;

import 'dart:math';

import 'common.dart';
import 'diff.dart';
import 'match.dart';

/// Class representing one patch operation.
class Patch {
  List<Diff> diffs = <Diff>[];
  int start1 = 0;
  int start2 = 0;
  int length1 = 0;
  int length2 = 0;

  /// Emulate GNU diff's format.
  ///
  /// Header: @@ -382,8 +481,9 @@
  ///
  /// Indices are printed as 1-based, not 0-based.
  /// Returns the GNU diff string.
  @override
  String toString() {
    String coords1, coords2;
    if (length1 == 0) {
      coords1 = '$start1,0';
    } else if (length1 == 1) {
      coords1 = (start1 + 1).toString();
    } else {
      coords1 = '${start1 + 1},$length1';
    }
    if (length2 == 0) {
      coords2 = '$start2,0';
    } else if (length2 == 1) {
      coords2 = (start2 + 1).toString();
    } else {
      coords2 = '${start2 + 1},$length2';
    }
    final text = StringBuffer('@@ -$coords1 +$coords2 @@\n');
    // Escape the body of the patch with %xx notation.
    // ignore: omit_local_variable_types
    for (Diff aDiff in diffs) {
      switch (aDiff.operation) {
        case DiffOperation.insert:
          text.write('+');
          break;
        case DiffOperation.delete:
          text.write('-');
          break;
        case DiffOperation.equal:
          text.write(' ');
          break;
      }
      text
        ..write(Uri.encodeFull(aDiff.text))
        ..write('\n');
    }
    return text.toString().replaceAll('%20', ' ');
  }
}

/// Take a list of patches and return a textual representation.
///
/// [patches] is a List of Patch objects.
/// Returns a text representation of patches.
String patchToText(List<Patch> patches) {
  final text = StringBuffer();
  // ignore: omit_local_variable_types
  for (Patch aPatch in patches) {
    text.write(aPatch);
  }
  return text.toString();
}

/// Parse a textual representation of patches and return a List of Patch objects.
///
/// [textLine] is a text representation of patches.
///
/// Returns a List of Patch objects.
///
/// Throws ArgumentError if invalid input.
List<Patch> patchFromText(String textLine) {
  final patches = <Patch>[];
  if (textLine.isEmpty) {
    return patches;
  }
  final text = textLine.split('\n');
  var textPointer = 0;
  final patchHeader = RegExp('^@@ -(\\d+),?(\\d*) \\+(\\d+),?(\\d*) @@\$');
  while (textPointer < text.length) {
    Match? m = patchHeader.firstMatch(text[textPointer]);
    if (m == null) {
      throw ArgumentError('Invalid patch string: ${text[textPointer]}');
    }
    final patch = Patch();
    patches.add(patch);
    patch.start1 = int.parse(m.group(1)!);
    if (m.group(2)!.isEmpty) {
      patch.start1--;
      patch.length1 = 1;
    } else if (m.group(2) == '0') {
      patch.length1 = 0;
    } else {
      patch.start1--;
      patch.length1 = int.parse(m.group(2)!);
    }

    patch.start2 = int.parse(m.group(3)!);
    if (m.group(4)!.isEmpty) {
      patch.start2--;
      patch.length2 = 1;
    } else if (m.group(4) == '0') {
      patch.length2 = 0;
    } else {
      patch.start2--;
      patch.length2 = int.parse(m.group(4)!);
    }
    textPointer++;

    while (textPointer < text.length) {
      if (text[textPointer].isNotEmpty) {
        final sign = text[textPointer][0];
        var line = '';
        try {
          line = Uri.decodeFull(text[textPointer].substring(1));
        } on ArgumentError {
          // Malformed URI sequence.
          throw ArgumentError('Illegal escape in patch_fromText: $line');
        }
        if (sign == '-') {
          // Deletion.
          patch.diffs.add(Diff(DiffOperation.delete, line));
        } else if (sign == '+') {
          // Insertion.
          patch.diffs.add(Diff(DiffOperation.insert, line));
        } else if (sign == ' ') {
          // Minor equality.
          patch.diffs.add(Diff(DiffOperation.equal, line));
        } else if (sign == '@') {
          // Start of next patch.
          break;
        } else {
          // WTF?
          throw ArgumentError('Invalid patch mode "$sign" in: $line');
        }
      }
      textPointer++;
    }
  }
  return patches;
}

/// Increase the context until it is unique,
/// but don't let the pattern expand beyond Match_MaxBits.
///
/// * [patch] is the patch to grow.
/// * [text] is the source text.
/// * [patchMargin] Chunk size for context length.
void patchAddContext(Patch patch, String text, int patchMargin) {
  if (text.isEmpty) {
    return;
  }
  var pattern = text.substring(patch.start2, patch.start2 + patch.length1);
  var padding = 0;

  // Look for the first and last matches of pattern in text.  If two different
  // matches are found, increase the pattern length.
  while ((text.indexOf(pattern) != text.lastIndexOf(pattern)) &&
      (pattern.length < ((bitsPerInt - patchMargin) - patchMargin))) {
    padding += patchMargin;
    pattern = text.substring(max(0, patch.start2 - padding), min(text.length, patch.start2 + patch.length1 + padding));
  }
  // Add one chunk for good luck.
  padding += patchMargin;

  // Add the prefix.
  final prefix = text.substring(max(0, patch.start2 - padding), patch.start2);
  if (prefix.isNotEmpty) {
    patch.diffs.insert(0, Diff(DiffOperation.equal, prefix));
  }
  // Add the suffix.
  final suffix = text.substring(patch.start2 + patch.length1, min(text.length, patch.start2 + patch.length1 + padding));
  if (suffix.isNotEmpty) {
    patch.diffs.add(Diff(DiffOperation.equal, suffix));
  }

  // Roll back the start points.
  patch.start1 -= prefix.length;
  patch.start2 -= prefix.length;
  // Extend the lengths.
  patch.length1 += prefix.length + suffix.length;
  patch.length2 += prefix.length + suffix.length;
}

/// Compute a List of Patches to turn text1 into text2.
///
/// Use diffs if provided, otherwise compute it ourselves.
/// There are four ways to call this function, depending on what data is
/// available to the caller:
///
/// * Method 1:
///   [a] = text1, [b] = text2
/// * Method 2:
///   [a] = diffs
/// * Method 3 (optimal):
///   [a] = text1, [b] = diffs
/// * Method 4 (deprecated, use method 3):
///   [a] = text1, [b] = text2, [c] = diffs
///
/// Returns a List of Patch objects.
List<Patch> patchMake(
  Object? a, {
  Object? b,
  Object? c,
  int diffEditCost = 4,
  double deleteThreshold = 0.5,
  int margin = 4,
}) {
  String text1;
  List<Diff> diffs;
  if (a is String && b is String && c == null) {
    // Method 1: text1, text2
    // Compute diffs from text1 and text2.
    text1 = a;
    diffs = diff(text1, b, checkLines: true);
    if (diffs.length > 2) {
      cleanupSemantic(diffs, from: 0);
      cleanupEfficiency(diffs, diffEditCost, from: 0);
    }
  } else if (a is List<Diff> && b == null && c == null) {
    // Method 2: diffs
    // Compute text1 from diffs.
    diffs = a;
    text1 = diffText1(diffs);
  } else if (a is String && b is List<Diff> && c == null) {
    // Method 3: text1, diffs
    text1 = a;
    diffs = b;
  } else if (a is String && b is String && c is List<Diff>) {
    // Method 4: text1, text2, diffs
    // text2 is not used.
    text1 = a;
    diffs = c;
  } else {
    throw ArgumentError('Unknown call format to patch_make.');
  }

  final patches = <Patch>[];
  if (diffs.isEmpty) {
    return patches; // Get rid of the null case.
  }
  var patch = Patch();
  final postpatchBuffer = StringBuffer();
  var charCount1 = 0; // Number of characters into the text1 string.
  var charCount2 = 0; // Number of characters into the text2 string.
  // Start with text1 (prepatch_text) and apply the diffs until we arrive at
  // text2 (postpatch_text). We recreate the patches one by one to determine
  // context info.
  var prepatchText = text1;
  var postpatchText = text1;
  for (var aDiff in diffs) {
    if (patch.diffs.isEmpty && aDiff.operation != DiffOperation.equal) {
      // A new patch starts here.
      patch.start1 = charCount1;
      patch.start2 = charCount2;
    }

    switch (aDiff.operation) {
      case DiffOperation.insert:
        patch.diffs.add(aDiff);
        patch.length2 += aDiff.text.length;
        postpatchBuffer.clear();
        postpatchBuffer
          ..write(postpatchText.substring(0, charCount2))
          ..write(aDiff.text)
          ..write(postpatchText.substring(charCount2));
        postpatchText = postpatchBuffer.toString();
        break;
      case DiffOperation.delete:
        patch.length1 += aDiff.text.length;
        patch.diffs.add(aDiff);
        postpatchBuffer.clear();
        postpatchBuffer
          ..write(postpatchText.substring(0, charCount2))
          ..write(postpatchText.substring(charCount2 + aDiff.text.length));
        postpatchText = postpatchBuffer.toString();
        break;
      case DiffOperation.equal:
        if (aDiff.text.length <= 2 * margin && patch.diffs.isNotEmpty && aDiff != diffs.last) {
          // Small equality inside a patch.
          patch.diffs.add(aDiff);
          patch.length1 += aDiff.text.length;
          patch.length2 += aDiff.text.length;
        }

        if (aDiff.text.length >= 2 * margin) {
          // Time for a new patch.
          if (patch.diffs.isNotEmpty) {
            patchAddContext(patch, prepatchText, margin);
            patches.add(patch);
            patch = Patch();
            // Unlike Unidiff, our patch lists have a rolling context.
            // http://code.google.com/p/google-diff-match-patch/wiki/Unidiff
            // Update prepatch text & pos to reflect the application of the
            // just completed patch.
            prepatchText = postpatchText;
            charCount1 = charCount2;
          }
        }
        break;
    }

    // Update the current character count.
    if (aDiff.operation != DiffOperation.insert) {
      charCount1 += aDiff.text.length;
    }
    if (aDiff.operation != DiffOperation.delete) {
      charCount2 += aDiff.text.length;
    }
  }
  // Pick up the leftover patch if not empty.
  if (patch.diffs.isNotEmpty) {
    patchAddContext(patch, prepatchText, margin);
    patches.add(patch);
  }

  return patches;
}

/// Given an array of patches, return another array that is identical.
/// [patches] is a List of Patch objects.
/// Returns a List of Patch objects.
List<Patch> patchDeepCopy(List<Patch> patches) {
  final patchesCopy = <Patch>[];
  for (var aPatch in patches) {
    final patchCopy = Patch();
    for (var aDiff in aPatch.diffs) {
      patchCopy.diffs.add(Diff(aDiff.operation, aDiff.text));
    }
    patchCopy.start1 = aPatch.start1;
    patchCopy.start2 = aPatch.start2;
    patchCopy.length1 = aPatch.length1;
    patchCopy.length2 = aPatch.length2;
    patchesCopy.add(patchCopy);
  }
  return patchesCopy;
}

/// Merge a set of patches onto the text.
///
/// Return a patched text, as well
/// as an array of true/false values indicating which patches were applied.
///
/// * [patches] is a List of Patch objects
/// * [text] is the old text.
///
/// Returns a two element List, containing the new text and a List of bool values.
List patchApply(
  List<Patch> patches,
  String text, {
  double deleteThreshold = 0.5,
  double matchThreshold = 0.5,
  int matchDistance = 1000,
  int margin = 4,
}) {
  if (patches.isEmpty) {
    return [text, []];
  }

  // Deep copy the patches so that no changes are made to originals.
  patches = patchDeepCopy(patches);

  final nullPadding = patchAddPadding(patches, margin: margin);
  text = '$nullPadding$text$nullPadding';
  patchSplitMax(patches, margin: margin);

  final textBuffer = StringBuffer();
  var x = 0;
  // delta keeps track of the offset between the expected and actual location
  // of the previous patch.  If there are patches expected at positions 10 and
  // 20, but the first patch was found at 12, delta is 2 and the second patch
  // has an effective expected position of 22.
  var delta = 0;
  final results = List<bool>.filled(patches.length, false);
  for (var aPatch in patches) {
    var expectedLoc = aPatch.start2 + delta;
    var text1 = diffText1(aPatch.diffs);
    int startLoc;
    var endLoc = -1;
    if (text1.length > bitsPerInt) {
      // patch_splitMax will only provide an oversized pattern in the case of
      // a monster delete.
      startLoc = match(
        text,
        text1.substring(0, bitsPerInt),
        expectedLoc,
        threshold: matchThreshold,
        distance: matchDistance,
      );
      if (startLoc != -1) {
        endLoc = match(
          text,
          text1.substring(text1.length - bitsPerInt),
          expectedLoc + text1.length - bitsPerInt,
          threshold: matchThreshold,
          distance: matchDistance,
        );
        if (endLoc == -1 || startLoc >= endLoc) {
          // Can't find valid trailing context.  Drop this patch.
          startLoc = -1;
        }
      }
    } else {
      startLoc = match(text, text1, expectedLoc, threshold: matchThreshold, distance: matchDistance);
    }
    if (startLoc == -1) {
      // No match found.  :(
      results[x] = false;
      // Subtract the delta for this failed patch from subsequent patches.
      delta -= aPatch.length2 - aPatch.length1;
    } else {
      // Found a match.  :)
      results[x] = true;
      delta = startLoc - expectedLoc;
      String text2;
      if (endLoc == -1) {
        text2 = text.substring(startLoc, min(startLoc + text1.length, text.length));
      } else {
        text2 = text.substring(startLoc, min(endLoc + bitsPerInt, text.length));
      }
      if (text1 == text2) {
        // Perfect match, just shove the replacement text in.
        textBuffer.clear();
        textBuffer
          ..write(text.substring(0, startLoc))
          ..write(diffText2(aPatch.diffs))
          ..write(text.substring(startLoc + text1.length));
        text = textBuffer.toString();
      } else {
        // Imperfect match.  Run a diff to get a framework of equivalent
        // indices.
        final diffs = diff(text1, text2, checkLines: false);
        if ((text1.length > bitsPerInt) && (levenshtein(diffs) / text1.length > deleteThreshold)) {
          // The end points match, but the content is unacceptably bad.
          results[x] = false;
        } else {
          cleanupSemanticLossless(diffs, from: 0);
          var index1 = 0;
          for (var aDiff in aPatch.diffs) {
            if (aDiff.operation != DiffOperation.equal) {
              var index2 = diffXIndex(diffs, index1);
              if (aDiff.operation == DiffOperation.insert) {
                // Insertion
                textBuffer.clear();
                textBuffer
                  ..write(text.substring(0, startLoc + index2))
                  ..write(aDiff.text)
                  ..write(text.substring(startLoc + index2));
                text = textBuffer.toString();
              } else if (aDiff.operation == DiffOperation.delete) {
                // Deletion
                textBuffer.clear();
                textBuffer
                  ..write(text.substring(0, startLoc + index2))
                  ..write(text.substring(startLoc + diffXIndex(diffs, index1 + aDiff.text.length)));
                text = textBuffer.toString();
              }
            }
            if (aDiff.operation != DiffOperation.delete) {
              index1 += aDiff.text.length;
            }
          }
        }
      }
    }
    x++;
  }
  // Strip the padding off.
  text = text.substring(nullPadding.length, text.length - nullPadding.length);
  return [text, results];
}

/// Add some padding on text start and end so that edges can match something.
///
/// Intended to be called only from within [patchApply].
///
/// [patches] is a List of Patch objects.
///
/// Returns the padding string added to each side.
String patchAddPadding(List<Patch> patches, {int margin = 4}) {
  final paddingLength = margin;
  final paddingCodes = <int>[];
  for (var x = 1; x <= paddingLength; x++) {
    paddingCodes.add(x);
  }
  var nullPadding = String.fromCharCodes(paddingCodes);

  // Bump all the patches forward.
  for (var aPatch in patches) {
    aPatch.start1 += paddingLength;
    aPatch.start2 += paddingLength;
  }

  // Add some padding on start of first diff.
  var patch = patches[0];
  var diffs = patch.diffs;
  if (diffs.isEmpty || diffs[0].operation != DiffOperation.equal) {
    // Add nullPadding equality.
    diffs.insert(0, Diff(DiffOperation.equal, nullPadding));
    patch.start1 -= paddingLength; // Should be 0.
    patch.start2 -= paddingLength; // Should be 0.
    patch.length1 += paddingLength;
    patch.length2 += paddingLength;
  } else if (paddingLength > diffs[0].text.length) {
    // Grow first equality.
    var firstDiff = diffs[0];
    var extraLength = paddingLength - firstDiff.text.length;
    firstDiff.text = '${nullPadding.substring(firstDiff.text.length)}${firstDiff.text}';
    patch.start1 -= extraLength;
    patch.start2 -= extraLength;
    patch.length1 += extraLength;
    patch.length2 += extraLength;
  }

  // Add some padding on end of last diff.
  patch = patches.last;
  diffs = patch.diffs;
  if (diffs.isEmpty || diffs.last.operation != DiffOperation.equal) {
    // Add nullPadding equality.
    diffs.add(Diff(DiffOperation.equal, nullPadding));
    patch.length1 += paddingLength;
    patch.length2 += paddingLength;
  } else if (paddingLength > diffs.last.text.length) {
    // Grow last equality.
    var lastDiff = diffs.last;
    var extraLength = paddingLength - lastDiff.text.length;
    lastDiff.text = '${lastDiff.text}${nullPadding.substring(0, extraLength)}';
    patch.length1 += extraLength;
    patch.length2 += extraLength;
  }

  return nullPadding;
}

/// Look through the [patches] and break up any which are longer than the
/// maximum limit of the match algorithm.
///
/// Intended to be called only from within [patchApply].
///
/// [patches] is a List of Patch objects.
void patchSplitMax(List<Patch> patches, {int margin = 4}) {
  final patchSize = bitsPerInt;
  for (var x = 0; x < patches.length; x++) {
    if (patches[x].length1 <= patchSize) {
      continue;
    }
    var bigPatch = patches[x];
    // Remove the big old patch.
    patches.removeRange(x, x + 1);
    x--;
    var start1 = bigPatch.start1;
    var start2 = bigPatch.start2;
    var precontext = '';
    while (bigPatch.diffs.isNotEmpty) {
      // Create one of several smaller patches.
      final patch = Patch();
      var empty = true;
      patch.start1 = start1 - precontext.length;
      patch.start2 = start2 - precontext.length;
      if (precontext.isNotEmpty) {
        patch.length1 = patch.length2 = precontext.length;
        patch.diffs.add(Diff(DiffOperation.equal, precontext));
      }
      while (bigPatch.diffs.isNotEmpty && patch.length1 < patchSize - margin) {
        var diffType = bigPatch.diffs[0].operation;
        var diffText = bigPatch.diffs[0].text;
        if (diffType == DiffOperation.insert) {
          // Insertions are harmless.
          patch.length2 += diffText.length;
          start2 += diffText.length;
          patch.diffs.add(bigPatch.diffs[0]);
          bigPatch.diffs.removeRange(0, 1);
          empty = false;
        } else if (diffType == DiffOperation.delete &&
            patch.diffs.length == 1 &&
            patch.diffs[0].operation == DiffOperation.equal &&
            diffText.length > 2 * patchSize) {
          // This is a large deletion.  Let it pass in one chunk.
          patch.length1 += diffText.length;
          start1 += diffText.length;
          empty = false;
          patch.diffs.add(Diff(diffType, diffText));
          bigPatch.diffs.removeRange(0, 1);
        } else {
          // Deletion or equality.  Only take as much as we can stomach.
          diffText = diffText.substring(0, min(diffText.length, patchSize - patch.length1 - margin));
          patch.length1 += diffText.length;
          start1 += diffText.length;
          if (diffType == DiffOperation.equal) {
            patch.length2 += diffText.length;
            start2 += diffText.length;
          } else {
            empty = false;
          }
          patch.diffs.add(Diff(diffType, diffText));
          if (diffText == bigPatch.diffs[0].text) {
            bigPatch.diffs.removeRange(0, 1);
          } else {
            bigPatch.diffs[0].text = bigPatch.diffs[0].text.substring(diffText.length);
          }
        }
      }
      // Compute the head context for the next patch.
      precontext = diffText2(patch.diffs);
      precontext = precontext.substring(max(0, precontext.length - margin));
      // Append the end context for this patch.
      String postcontext;
      if (diffText1(bigPatch.diffs).length > margin) {
        postcontext = diffText1(bigPatch.diffs).substring(0, margin);
      } else {
        postcontext = diffText1(bigPatch.diffs);
      }
      if (postcontext.isNotEmpty) {
        patch.length1 += postcontext.length;
        patch.length2 += postcontext.length;
        if (patch.diffs.isNotEmpty && patch.diffs.last.operation == DiffOperation.equal) {
          patch.diffs.last.text = '${patch.diffs.last.text}$postcontext';
        } else {
          patch.diffs.add(Diff(DiffOperation.equal, postcontext));
        }
      }
      if (!empty) {
        patches.insert(++x, patch);
      }
    }
  }
}
