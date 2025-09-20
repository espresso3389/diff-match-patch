/// Main functions
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

/// Find the differences between two texts.  Simplifies the problem by
/// stripping any common prefix or suffix off the texts before diffing.
///
/// * [text1] is the old string to be diffed.
/// * [text2] is the new string to be diffed.
/// * [checkLines] is an optional speedup flag.  If false, then don't
///   run a line-level diff first to identify the changed areas.
///   Defaults to true, which does a faster, slightly less optimal diff.
/// * [willContinue] is an optional callback that is invoked periodically.
///
/// Returns a List of Diff objects.
List<Diff> diff(String text1, String text2, {bool checkLines = true, WillContinue? willContinue}) {
  final diffs = <Diff>[];
  _diff(
    diffs,
    text1,
    text2,
    checkLines: checkLines,
    willContinue: willContinue != null ? () => willContinue.call(diffs) : null,
  );
  return diffs;
}

typedef WillContinue0 = bool Function();

void _diff(List<Diff> diffs, String text1, String text2, {bool checkLines = true, WillContinue0? willContinue}) {
  final from = diffs.length;

  // Check for equality (speedup).
  if (text1 == text2) {
    if (text1.isNotEmpty) {
      diffs.add(Diff(DiffOperation.equal, text1));
    }
    return;
  }

  // Trim off common prefix (speedup).
  var commonLength = calcCommonPrefix(text1, text2);
  final commonPrefix = text1.substring(0, commonLength);
  text1 = text1.substring(commonLength);
  text2 = text2.substring(commonLength);

  // Trim off common suffix (speedup).
  commonLength = calcCommonSuffix(text1, text2);
  var commonSuffix = text1.substring(text1.length - commonLength);
  text1 = text1.substring(0, text1.length - commonLength);
  text2 = text2.substring(0, text2.length - commonLength);

  // Compute the diff on the middle block.
  _diffCompute(diffs, text1, text2, checkLines, willContinue);

  // Restore the prefix and suffix.
  if (commonPrefix.isNotEmpty) {
    diffs.insert(0, Diff(DiffOperation.equal, commonPrefix));
  }
  if (commonSuffix.isNotEmpty) {
    diffs.add(Diff(DiffOperation.equal, commonSuffix));
  }

  cleanupMerge(diffs, from: from);
}

/// Find the differences between two texts.  Assumes that the texts do not
/// have any common prefix or suffix.
///
/// * [text1] is the old string to be diffed.
/// * [text2] is the new string to be diffed.
/// * [checkLines] is a speedup flag.  If false, then don't run a
///   line-level diff first to identify the changed areas.
///   If true, then run a faster slightly less optimal diff.
/// * [willContinue] is an optional callback that is invoked periodically.
///
/// Returns a List of Diff objects.
void _diffCompute(List<Diff> diffs, String text1, String text2, bool checkLines, WillContinue0? willContinue) {
  if (text1.isEmpty) {
    // Just add some text (speedup).
    diffs.add(Diff(DiffOperation.insert, text2));
    return;
  }

  if (text2.isEmpty) {
    // Just delete some text (speedup).
    diffs.add(Diff(DiffOperation.delete, text1));
    return;
  }

  var longText = text1.length > text2.length ? text1 : text2;
  var shortText = text1.length > text2.length ? text2 : text1;
  var i = longText.indexOf(shortText);
  if (i != -1) {
    // Shorter text is inside the longer text (speedup).
    var op = (text1.length > text2.length) ? DiffOperation.delete : DiffOperation.insert;
    diffs.add(Diff(op, longText.substring(0, i)));
    diffs.add(Diff(DiffOperation.equal, shortText));
    diffs.add(Diff(op, longText.substring(i + shortText.length)));
    return;
  }

  if (shortText.length == 1) {
    // Single character string.
    // After the previous speedup, the character can't be an equality.
    diffs.add(Diff(DiffOperation.delete, text1));
    diffs.add(Diff(DiffOperation.insert, text2));
    return;
  }

  // Check to see if the problem can be split in two.
  final hm = diffHalfMatch(text1, text2);
  if (hm != null) {
    // A half-match was found, sort out the return data.
    final text1A = hm[0];
    final text1B = hm[1];
    final text2A = hm[2];
    final text2B = hm[3];
    final midCommon = hm[4];
    // Send both pairs off for separate processing.
    _diff(diffs, text1A, text2A, checkLines: checkLines, willContinue: willContinue);
    diffs.add(Diff(DiffOperation.equal, midCommon));
    _diff(diffs, text1B, text2B, checkLines: checkLines, willContinue: willContinue);
    return;
  }

  if (checkLines && text1.length > 100 && text2.length > 100) {
    _diffLineMode(diffs, text1, text2, willContinue);
    return;
  }

  diffBisect(diffs, text1, text2, willContinue);
}

/// Do a quick line-level diff on both strings, then rediff the parts for
/// greater accuracy.
/// This speedup can produce non-minimal diffs.
///
/// * [text1] is the old string to be diffed.
/// * [text2] is the new string to be diffed.
/// * [willContinue] is an optional callback that is invoked periodically.
///
/// Returns a List of Diff objects.
void _diffLineMode(List<Diff> diffs, String text1, String text2, WillContinue0? willContinue) {
  final from = diffs.length;
  // Scan the text on a line-by-line basis first.
  final a = linesToChars(text1, text2);
  text1 = a['chars1'] as String;
  text2 = a['chars2'] as String;
  final lineArray = a['lineArray'] as List<String>? ?? [];

  _diff(diffs, text1, text2, checkLines: false, willContinue: willContinue);

  // Convert the diff back to original text.
  charsToLines(diffs, lineArray, from: from);
  // Eliminate freak matches (e.g. blank lines)
  cleanupSemantic(diffs, from: from);

  // Rediff any replacement blocks, this time character-by-character.
  // Add a dummy entry at the end.
  diffs.add(Diff(DiffOperation.equal, ''));
  var pointer = 0;
  var countDelete = 0;
  var countInsert = 0;
  final textDelete = StringBuffer();
  final textInsert = StringBuffer();
  while (pointer < diffs.length) {
    switch (diffs[pointer].operation) {
      case DiffOperation.insert:
        countInsert++;
        textInsert.write(diffs[pointer].text);
        break;
      case DiffOperation.delete:
        countDelete++;
        textDelete.write(diffs[pointer].text);
        break;
      case DiffOperation.equal:
        // Upon reaching an equality, check for prior redundancies.
        if (countDelete >= 1 && countInsert >= 1) {
          // Delete the offending records and add the merged ones.
          diffs.removeRange(pointer - countDelete - countInsert, pointer);
          pointer = pointer - countDelete - countInsert;
          final a = <Diff>[];
          _diff(a, textDelete.toString(), textInsert.toString(), checkLines: false, willContinue: willContinue);
          for (var j = a.length - 1; j >= 0; j--) {
            diffs.insert(pointer, a[j]);
          }
          pointer = pointer + a.length;
        }
        countInsert = 0;
        countDelete = 0;
        textDelete.clear();
        textInsert.clear();
        break;
    }
    pointer++;
  }
  diffs.removeLast(); // Remove the dummy entry at the end.
}

/// Find the 'middle snake' of a diff, split the problem in two
/// and return the recursively constructed diff.
///
/// See Myers 1986 paper: An O(ND) Difference Algorithm and Its Variations.
///
/// * [text1] is the old string to be diffed.
/// * [text2] is the new string to be diffed.
/// * [willContinue] is an optional callback that is invoked periodically.
///
/// Returns a List of Diff objects.
void diffBisect(List<Diff> diffs, String text1, String text2, WillContinue0? willContinue) {
  // Cache the text lengths to prevent multiple calls.
  final text1Length = text1.length;
  final text2Length = text2.length;
  final maxD = (text1Length + text2Length + 1) ~/ 2;
  final vOffset = maxD;
  final vLength = 2 * maxD;
  final v1 = List<int>.filled(vLength, 0);
  final v2 = List<int>.filled(vLength, 0);
  for (var x = 0; x < vLength; x++) {
    v1[x] = -1;
    v2[x] = -1;
  }
  v1[vOffset + 1] = 0;
  v2[vOffset + 1] = 0;
  final delta = text1Length - text2Length;
  // If the total number of characters is odd, then the front path will
  // collide with the reverse path.
  final front = (delta % 2 != 0);
  // Offsets for start and end of k loop.
  // Prevents mapping of space beyond the grid.
  var k1start = 0;
  var k1end = 0;
  var k2start = 0;
  var k2end = 0;
  for (var d = 0; d < maxD; d++) {
    // Bail out if willContinue returns false.
    if (willContinue?.call() == false) {
      break;
    }

    // Walk the front path one step.
    for (var k1 = -d + k1start; k1 <= d - k1end; k1 += 2) {
      var k1Offset = vOffset + k1;
      var x1 = 0;
      if (k1 == -d || k1 != d && v1[k1Offset - 1] < v1[k1Offset + 1]) {
        x1 = v1[k1Offset + 1];
      } else {
        x1 = v1[k1Offset - 1] + 1;
      }
      var y1 = x1 - k1;
      while (x1 < text1Length && y1 < text2Length && text1[x1] == text2[y1]) {
        x1++;
        y1++;
      }
      v1[k1Offset] = x1;
      if (x1 > text1Length) {
        // Ran off the right of the graph.
        k1end += 2;
      } else if (y1 > text2Length) {
        // Ran off the bottom of the graph.
        k1start += 2;
      } else if (front) {
        var k2Offset = vOffset + delta - k1;
        if (k2Offset >= 0 && k2Offset < vLength && v2[k2Offset] != -1) {
          // Mirror x2 onto top-left coordinate system.
          var x2 = text1Length - v2[k2Offset];
          if (x1 >= x2) {
            // Overlap detected.
            _diffBisectSplit(diffs, text1, text2, x1, y1, willContinue);
            return;
          }
        }
      }
    }

    // Walk the reverse path one step.
    for (var k2 = -d + k2start; k2 <= d - k2end; k2 += 2) {
      var k2Offset = vOffset + k2;
      var x2 = 0;
      if (k2 == -d || k2 != d && v2[k2Offset - 1] < v2[k2Offset + 1]) {
        x2 = v2[k2Offset + 1];
      } else {
        x2 = v2[k2Offset - 1] + 1;
      }
      var y2 = x2 - k2;
      while (x2 < text1Length && y2 < text2Length && text1[text1Length - x2 - 1] == text2[text2Length - y2 - 1]) {
        x2++;
        y2++;
      }
      v2[k2Offset] = x2;
      if (x2 > text1Length) {
        // Ran off the left of the graph.
        k2end += 2;
      } else if (y2 > text2Length) {
        // Ran off the top of the graph.
        k2start += 2;
      } else if (!front) {
        var k1Offset = vOffset + delta - k2;
        if (k1Offset >= 0 && k1Offset < vLength && v1[k1Offset] != -1) {
          var x1 = v1[k1Offset];
          var y1 = vOffset + x1 - k1Offset;
          // Mirror x2 onto top-left coordinate system.
          x2 = text1Length - x2;
          if (x1 >= x2) {
            // Overlap detected.
            _diffBisectSplit(diffs, text1, text2, x1, y1, willContinue);
            return;
          }
        }
      }
    }
  }
  // Diff took too long and hit the willContinue or
  // number of diffs equals number of characters, no commonality at all.
  diffs.addAll([Diff(DiffOperation.delete, text1), Diff(DiffOperation.insert, text2)]);
  return;
}

/// Given the location of the 'middle snake', split the diff in two parts
/// and recurse.
///
/// * [text1] is the old string to be diffed.
/// * [text2] is the new string to be diffed.
/// * [x] is the index of split point in text1.
/// * [y] is the index of split point in text2.
/// * [willContinue] is an optional callback that is invoked periodically.
///
/// Returns a List of Diff objects.
void _diffBisectSplit(List<Diff> diffs, String text1, String text2, int x, int y, WillContinue0? willContinue) {
  final text1a = text1.substring(0, x);
  final text2a = text2.substring(0, y);
  final text1b = text1.substring(x);
  final text2b = text2.substring(y);

  // Compute both diffs serially.
  _diff(diffs, text1a, text2a, checkLines: false, willContinue: willContinue);
  _diff(diffs, text1b, text2b, checkLines: false, willContinue: willContinue);
}
