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

import 'dart:collection';
import 'dart:math';

import 'api.dart' show WillContinue;

part 'diff/cleanup.dart';
part 'diff/delta.dart';
part 'diff/diff.dart';
part 'diff/half_match.dart';
part 'diff/main.dart';
part 'diff/utils.dart';
