import 'package:drift/drift.dart';
import 'package:kover/database/app_database.dart';
import 'package:kover/models/enums/format.dart';

/// Matches chapter [format] values whose pages are single images and therefore
/// support bookmarks.
Expression<bool> isBookmarkableChapterFormat(Expression<String> format) =>
    format.isIn([Format.image.name, Format.archive.name]);

/// Build an OR of [columns] each containing [query].
Expression<bool> containsAny(
  String query,
  Iterable<GeneratedColumn<String>> columns,
) {
  return columns
      .map((column) => column.contains(query))
      .reduce((a, b) => a | b);
}

/// Series title columns searched and ranked across queries.
Iterable<GeneratedColumn<String>> seriesTitleColumns(AppDatabase db) => [
  db.series.name,
  db.series.sortName,
  db.series.localizedName,
  db.series.originalName,
];

/// Build an AND expression across whitespace-separated tokens of [query].
Expression<bool> matchesAllTokens(
  String query,
  Expression<bool> Function(String token) matcher,
) {
  final trimmed = query.trim();
  if (trimmed.isEmpty) return const Constant(true);
  return trimmed.split(RegExp(r'\s+')).map(matcher).reduce((a, b) => a & b);
}

/// Match [query] where at least one token matches [itemMatcher] and all tokens
/// match either [itemMatcher] or [parentMatcher].
Expression<bool> matchesTokensWithParent(
  String query,
  Expression<bool> Function(String token) itemMatcher,
  Expression<bool> Function(String token) parentMatcher,
) {
  final trimmed = query.trim();
  if (trimmed.isEmpty) return const Constant(false);
  final tokens = trimmed.split(RegExp(r'\s+'));
  if (tokens.length == 1) return itemMatcher(tokens.single);
  return tokens
          .map((t) => itemMatcher(t) | parentMatcher(t))
          .reduce((a, b) => a & b) &
      tokens.map(itemMatcher).reduce((a, b) => a | b);
}

/// Subquery selecting `people.id` rows matching [token] by name or alias.
BaseSelectStatement matchingPersonIds(AppDatabase db, String token) {
  final aliasToken = token.replaceAll(RegExp(r'[\[\]",]'), '');
  final match = aliasToken.isEmpty
      ? db.people.name.contains(token)
      : db.people.name.contains(token) |
            db.people.aliases.cast<String>().contains(aliasToken);
  return db.selectOnly(db.people)
    ..addColumns([db.people.id])
    ..where(match);
}

BaseSelectStatement matchingGenreIds(AppDatabase db, String token) =>
    db.selectOnly(db.genres)
      ..addColumns([db.genres.id])
      ..where(db.genres.label.contains(token));

BaseSelectStatement matchingTagIds(AppDatabase db, String token) =>
    db.selectOnly(db.tags)
      ..addColumns([db.tags.id])
      ..where(db.tags.label.contains(token));

/// Rank full-title (`0`), partial-title (`1`), and metadata-only (`2`) matches.
Expression<int> titleMatchRank(
  String query,
  Iterable<GeneratedColumn<String>> columns,
) {
  final tokens = query.trim().split(RegExp(r'\s+'));
  Expression<bool> matchTitle(String token) => containsAny(token, columns);
  return CaseWhenExpression<int>(
    cases: [
      CaseWhen(
        tokens.map(matchTitle).reduce((a, b) => a & b),
        then: const Constant(0),
      ),
      CaseWhen(
        tokens.map(matchTitle).reduce((a, b) => a | b),
        then: const Constant(1),
      ),
    ],
    orElse: const Constant(2),
  );
}

/// Progress ratio (pages read / total pages) as a double expression.
Expression<double> progressRatio(
  Expression<int> pagesReadSum,
  Expression<int> totalPages,
) {
  return pagesReadSum.cast<double>() / totalPages.cast<double>();
}

/// Whether a set of [pagesReadSum] is unread against [totalPages].
Expression<bool> hasUnreadProgress(
  Expression<int> pagesReadSum,
  Expression<int> totalPages,
) {
  return pagesReadSum.isNull() | pagesReadSum.isSmallerThan(totalPages);
}
