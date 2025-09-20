/// Cleanup functions
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

// Define some regex patterns for matching boundaries.
RegExp _nonAlphaNumericRegex = RegExp(r'[^a-zA-Z0-9]');
RegExp _whitespaceRegex = RegExp(r'\s');
RegExp _linebreakRegex = RegExp(r'[\r\n]');
RegExp _blanklineEndRegex = RegExp(r'\n\r?\n$');
RegExp _blanklineStartRegex = RegExp(r'^\r?\n\r?\n');

/// Reduce the number of edits by eliminating semantically trivial equalities.
///
/// [diffs] is a List of Diff objects.
void cleanupSemantic(List<Diff> diffs, {required int from}) {
  var changes = false;
  // Stack of indices where equalities are found.
  final equalities = <int>[];
  // Always equal to diffs[equalities.last()].text
  String? lastEquality;
  var pointer = from; // Index of current position.
  // Number of characters that changed prior to the equality.
  var lengthInsertions1 = 0;
  var lengthDeletions1 = 0;
  // Number of characters that changed after the equality.
  var lengthInsertions2 = 0;
  var lengthDeletions2 = 0;
  while (pointer < diffs.length) {
    if (diffs[pointer].operation == DiffOperation.equal) {
      // Equality found.
      equalities.add(pointer);
      lengthInsertions1 = lengthInsertions2;
      lengthDeletions1 = lengthDeletions2;
      lengthInsertions2 = 0;
      lengthDeletions2 = 0;
      lastEquality = diffs[pointer].text;
    } else {
      // An insertion or deletion.
      if (diffs[pointer].operation == DiffOperation.insert) {
        lengthInsertions2 += diffs[pointer].text.length;
      } else {
        lengthDeletions2 += diffs[pointer].text.length;
      }
      // Eliminate an equality that is smaller or equal to the edits on both
      // sides of it.
      if (lastEquality != null &&
          (lastEquality.length <= max(lengthInsertions1, lengthDeletions1)) &&
          (lastEquality.length <= max(lengthInsertions2, lengthDeletions2))) {
        // Duplicate record.
        diffs.insert(equalities.last, Diff(DiffOperation.delete, lastEquality));
        // Change second copy to insert.
        diffs[equalities.last + 1].operation = DiffOperation.insert;
        // Throw away the equality we just deleted.
        equalities.removeLast();
        // Throw away the previous equality (it needs to be reevaluated).
        if (equalities.isNotEmpty) {
          equalities.removeLast();
        }
        pointer = from + (equalities.isEmpty ? -1 : equalities.last);
        lengthInsertions1 = 0; // Reset the counters.
        lengthDeletions1 = 0;
        lengthInsertions2 = 0;
        lengthDeletions2 = 0;
        lastEquality = null;
        changes = true;
      }
    }
    pointer++;
  }

  // Normalize the diff.
  if (changes) {
    cleanupMerge(diffs, from: from);
  }
  cleanupSemanticLossless(diffs, from: from);

  // Find any overlaps between deletions and insertions.
  // e.g: <del>abcxxx</del><ins>xxxdef</ins>
  //   -> <del>abc</del>xxx<ins>def</ins>
  // e.g: <del>xxxabc</del><ins>defxxx</ins>
  //   -> <ins>def</ins>xxx<del>abc</del>
  // Only extract an overlap if it is as big as the edit ahead or behind it.
  pointer = from + 1;
  while (pointer < diffs.length) {
    if (diffs[pointer - 1].operation == DiffOperation.delete && diffs[pointer].operation == DiffOperation.insert) {
      var deletion = diffs[pointer - 1].text;
      var insertion = diffs[pointer].text;
      var overlapLength1 = calcCommonOverlap(deletion, insertion);
      var overlapLength2 = calcCommonOverlap(insertion, deletion);
      if (overlapLength1 >= overlapLength2) {
        if (overlapLength1 >= deletion.length / 2 || overlapLength1 >= insertion.length / 2) {
          // Overlap found.
          // Insert an equality and trim the surrounding edits.
          diffs.insert(pointer, Diff(DiffOperation.equal, insertion.substring(0, overlapLength1)));
          diffs[pointer - 1].text = deletion.substring(0, deletion.length - overlapLength1);
          diffs[pointer + 1].text = insertion.substring(overlapLength1);
          pointer++;
        }
      } else {
        if (overlapLength2 >= deletion.length / 2 || overlapLength2 >= insertion.length / 2) {
          // Reverse overlap found.
          // Insert an equality and swap and trim the surrounding edits.
          diffs.insert(pointer, Diff(DiffOperation.equal, deletion.substring(0, overlapLength2)));
          diffs[pointer - 1] = Diff(DiffOperation.insert, insertion.substring(0, insertion.length - overlapLength2));
          diffs[pointer + 1] = Diff(DiffOperation.delete, deletion.substring(overlapLength2));
          pointer++;
        }
      }
      pointer++;
    }
    pointer++;
  }
}

/// Look for single edits surrounded on both sides by equalities
/// which can be shifted sideways to align the edit to a word boundary.
///
/// e.g: The c<ins>at c</ins>ame. -> The <ins>cat </ins>came.
///
/// [diffs] is a List of Diff objects.
void cleanupSemanticLossless(List<Diff> diffs, {required int from}) {
  /// Given two strings, compute a score representing whether the internal
  /// boundary falls on logical boundaries.
  /// Scores range from 6 (best) to 0 (worst).
  /// Closure, but does not reference any external variables.
  /// [one] the first string.
  /// [two] the second string.
  /// Returns the score.

  int cleanupSemanticScore(String one, String two) {
    if (one.isEmpty || two.isEmpty) {
      // Edges are the best.
      return 6;
    }

    // Each port of this function behaves slightly differently due to
    // subtle differences in each language's definition of things like
    // 'whitespace'.  Since this function's purpose is largely cosmetic,
    // the choice has been made to use each language's native features
    // rather than force total conformity.
    var char1 = one[one.length - 1];
    var char2 = two[0];
    var nonAlphaNumeric1 = char1.contains(_nonAlphaNumericRegex);
    var nonAlphaNumeric2 = char2.contains(_nonAlphaNumericRegex);
    var whitespace1 = nonAlphaNumeric1 && char1.contains(_whitespaceRegex);
    var whitespace2 = nonAlphaNumeric2 && char2.contains(_whitespaceRegex);
    var lineBreak1 = whitespace1 && char1.contains(_linebreakRegex);
    var lineBreak2 = whitespace2 && char2.contains(_linebreakRegex);
    var blankLine1 = lineBreak1 && one.contains(_blanklineEndRegex);
    var blankLine2 = lineBreak2 && two.contains(_blanklineStartRegex);

    if (blankLine1 || blankLine2) {
      // Five points for blank lines.
      return 5;
    } else if (lineBreak1 || lineBreak2) {
      // Four points for line breaks.
      return 4;
    } else if (nonAlphaNumeric1 && !whitespace1 && whitespace2) {
      // Three points for end of sentences.
      return 3;
    } else if (whitespace1 || whitespace2) {
      // Two points for whitespace.
      return 2;
    } else if (nonAlphaNumeric1 || nonAlphaNumeric2) {
      // One point for non-alphanumeric.
      return 1;
    }
    return 0;
  }

  var pointer = from + 1;
  // Intentionally ignore the first and last element (don't need checking).
  while (pointer < diffs.length - 1) {
    if (diffs[pointer - 1].operation == DiffOperation.equal && diffs[pointer + 1].operation == DiffOperation.equal) {
      // This is a single edit surrounded by equalities.
      var equality1 = diffs[pointer - 1].text;
      var edit = diffs[pointer].text;
      var equality2 = diffs[pointer + 1].text;

      // First, shift the edit as far left as possible.
      var commonOffset = calcCommonSuffix(equality1, edit);
      if (commonOffset != 0) {
        var commonString = edit.substring(edit.length - commonOffset);
        equality1 = equality1.substring(0, equality1.length - commonOffset);
        edit = '$commonString${edit.substring(0, edit.length - commonOffset)}';
        equality2 = '$commonString$equality2';
      }

      // Second, step character by character right, looking for the best fit.
      var bestEquality1 = equality1;
      var bestEdit = edit;
      var bestEquality2 = equality2;
      var bestScore = cleanupSemanticScore(equality1, edit) + cleanupSemanticScore(edit, equality2);
      while (edit.isNotEmpty && equality2.isNotEmpty && edit[0] == equality2[0]) {
        equality1 = '$equality1${edit[0]}';
        edit = '${edit.substring(1)}${equality2[0]}';
        equality2 = equality2.substring(1);
        var score = cleanupSemanticScore(equality1, edit) + cleanupSemanticScore(edit, equality2);
        // The >= encourages trailing rather than leading whitespace on edits.
        if (score >= bestScore) {
          bestScore = score;
          bestEquality1 = equality1;
          bestEdit = edit;
          bestEquality2 = equality2;
        }
      }

      if (diffs[pointer - 1].text != bestEquality1) {
        // We have an improvement, save it back to the diff.
        if (bestEquality1.isNotEmpty) {
          diffs[pointer - 1].text = bestEquality1;
        } else {
          diffs.removeRange(pointer - 1, pointer);
          pointer--;
        }
        diffs[pointer].text = bestEdit;
        if (bestEquality2.isNotEmpty) {
          diffs[pointer + 1].text = bestEquality2;
        } else {
          diffs.removeRange(pointer + 1, pointer + 2);
          pointer--;
        }
      }
    }
    pointer++;
  }
}

/// Reduce the number of edits by eliminating operationally trivial equalities.
///
/// [diffs] is a List of Diff objects.
void cleanupEfficiency(List<Diff> diffs, int diffEditCost, {required int from}) {
  var changes = false;
  // Stack of indices where equalities are found.
  final equalities = <int>[];
  // Always equal to diffs[equalities.last()].text
  String? lastEquality;
  var pointer = from; // Index of current position.
  // Is there an insertion operation before the last equality.
  var preIns = false;
  // Is there a deletion operation before the last equality.
  var preDel = false;
  // Is there an insertion operation after the last equality.
  var postIns = false;
  // Is there a deletion operation after the last equality.
  var postDel = false;
  while (pointer < diffs.length) {
    if (diffs[pointer].operation == DiffOperation.equal) {
      // Equality found.
      if (diffs[pointer].text.length < diffEditCost && (postIns || postDel)) {
        // Candidate found.
        equalities.add(pointer);
        preIns = postIns;
        preDel = postDel;
        lastEquality = diffs[pointer].text;
      } else {
        // Not a candidate, and can never become one.
        equalities.clear();
        lastEquality = null;
      }
      postIns = postDel = false;
    } else {
      // An insertion or deletion.
      if (diffs[pointer].operation == DiffOperation.delete) {
        postDel = true;
      } else {
        postIns = true;
      }
      /*
       * Five types to be split:
       * <ins>A</ins><del>B</del>XY<ins>C</ins><del>D</del>
       * <ins>A</ins>X<ins>C</ins><del>D</del>
       * <ins>A</ins><del>B</del>X<ins>C</ins>
       * <ins>A</del>X<ins>C</ins><del>D</del>
       * <ins>A</ins><del>B</del>X<del>C</del>
       */
      if (lastEquality != null &&
          ((preIns && preDel && postIns && postDel) ||
              ((lastEquality.length < diffEditCost / 2) &&
                  ((preIns ? 1 : 0) + (preDel ? 1 : 0) + (postIns ? 1 : 0) + (postDel ? 1 : 0)) == 3))) {
        // Duplicate record.
        diffs.insert(equalities.last, Diff(DiffOperation.delete, lastEquality));
        // Change second copy to insert.
        diffs[equalities.last + 1].operation = DiffOperation.insert;
        equalities.removeLast(); // Throw away the equality we just deleted.
        lastEquality = null;
        if (preIns && preDel) {
          // No changes made which could affect previous entry, keep going.
          postIns = postDel = true;
          equalities.clear();
        } else {
          if (equalities.isNotEmpty) {
            equalities.removeLast();
          }
          pointer = from + (equalities.isEmpty ? -1 : equalities.last);
          postIns = postDel = false;
        }
        changes = true;
      }
    }
    pointer++;
  }

  if (changes) {
    cleanupMerge(diffs, from: from);
  }
}

/// Reorder and merge like edit sections.  Merge equalities.
/// Any edit section can move as long as it doesn't cross an equality.
///
/// [diffs] is a List of Diff objects.
void cleanupMerge(List<Diff> diffs, {required int from}) {
  diffs.add(Diff(DiffOperation.equal, '')); // Add a dummy entry at the end.
  var pointer = from;
  var countDelete = 0;
  var countInsert = 0;
  var textDelete = '';
  var textInsert = '';
  int commonLength;
  while (pointer < diffs.length) {
    switch (diffs[pointer].operation) {
      case DiffOperation.insert:
        countInsert++;
        textInsert = '$textInsert${diffs[pointer].text}';
        pointer++;
        break;
      case DiffOperation.delete:
        countDelete++;
        textDelete = '$textDelete${diffs[pointer].text}';
        pointer++;
        break;
      case DiffOperation.equal:
        // Upon reaching an equality, check for prior redundancies.
        if (countDelete + countInsert > 1) {
          if (countDelete != 0 && countInsert != 0) {
            // Factor out any common prefixes.
            commonLength = calcCommonPrefix(textInsert, textDelete);
            if (commonLength != 0) {
              if ((pointer - countDelete - countInsert) > 0 &&
                  diffs[pointer - countDelete - countInsert - 1].operation == DiffOperation.equal) {
                final i = pointer - countDelete - countInsert - 1;
                diffs[i].text =
                    '${diffs[i].text}'
                    '${textInsert.substring(0, commonLength)}';
              } else {
                diffs.insert(0, Diff(DiffOperation.equal, textInsert.substring(0, commonLength)));
                pointer++;
              }
              textInsert = textInsert.substring(commonLength);
              textDelete = textDelete.substring(commonLength);
            }
            // Factor out any common suffixes.
            commonLength = calcCommonSuffix(textInsert, textDelete);
            if (commonLength != 0) {
              diffs[pointer].text = '${textInsert.substring(textInsert.length - commonLength)}${diffs[pointer].text}';
              textInsert = textInsert.substring(0, textInsert.length - commonLength);
              textDelete = textDelete.substring(0, textDelete.length - commonLength);
            }
          }
          // Delete the offending records and add the merged ones.
          if (countDelete == 0) {
            diffs.removeRange(pointer - countInsert, pointer);
            diffs.insert(pointer - countInsert, Diff(DiffOperation.insert, textInsert));
          } else if (countInsert == 0) {
            diffs.removeRange(pointer - countDelete, pointer);
            diffs.insert(pointer - countDelete, Diff(DiffOperation.delete, textDelete));
          } else {
            diffs.removeRange(pointer - countDelete - countInsert, pointer);
            diffs.insert(pointer - countDelete - countInsert, Diff(DiffOperation.insert, textInsert));
            diffs.insert(pointer - countDelete - countInsert, Diff(DiffOperation.delete, textDelete));
          }
          pointer = pointer - countDelete - countInsert + (countDelete == 0 ? 0 : 1) + (countInsert == 0 ? 0 : 1) + 1;
        } else if (pointer != 0 && diffs[pointer - 1].operation == DiffOperation.equal) {
          // Merge this equality with the previous one.
          diffs[pointer - 1].text = '${diffs[pointer - 1].text}${diffs[pointer].text}';
          diffs.removeRange(pointer, pointer + 1);
        } else {
          pointer++;
        }
        countInsert = 0;
        countDelete = 0;
        textDelete = '';
        textInsert = '';
        break;
    }
  }
  if (diffs.last.text.isEmpty) {
    diffs.removeLast(); // Remove the dummy entry at the end.
  }

  // Second pass: look for single edits surrounded on both sides by equalities
  // which can be shifted sideways to eliminate an equality.
  // e.g: A<ins>BA</ins>C -> <ins>AB</ins>AC
  var changes = false;
  pointer = from + 1;
  // Intentionally ignore the first and last element (don't need checking).
  while (pointer < diffs.length - 1) {
    if (diffs[pointer - 1].operation == DiffOperation.equal && diffs[pointer + 1].operation == DiffOperation.equal) {
      // This is a single edit surrounded by equalities.
      if (diffs[pointer].text.endsWith(diffs[pointer - 1].text)) {
        // Shift the edit over the previous equality.
        diffs[pointer].text =
            '${diffs[pointer - 1].text}'
            '${diffs[pointer].text.substring(0, diffs[pointer].text.length - diffs[pointer - 1].text.length)}';
        diffs[pointer + 1].text = '${diffs[pointer - 1].text}${diffs[pointer + 1].text}';
        diffs.removeRange(pointer - 1, pointer);
        changes = true;
      } else if (diffs[pointer].text.startsWith(diffs[pointer + 1].text)) {
        // Shift the edit over the next equality.
        diffs[pointer - 1].text = '${diffs[pointer - 1].text}${diffs[pointer + 1].text}';
        diffs[pointer].text =
            '${diffs[pointer].text.substring(diffs[pointer + 1].text.length)}'
            '${diffs[pointer + 1].text}';
        diffs.removeRange(pointer + 1, pointer + 2);
        changes = true;
      }
    }
    pointer++;
  }
  // If shifts were made, the diff needs reordering and another shift sweep.
  if (changes) {
    cleanupMerge(diffs, from: from);
  }
}
