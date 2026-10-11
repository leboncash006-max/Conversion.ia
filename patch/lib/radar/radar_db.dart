import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../services/history.dart';

/// Recherche Leboncoin surveillée par le radar.
class RadarSearch {
  final int? id;
  final String name; // = titre de la notification Leboncoin
  final String url;
  final bool active;
  final double maxPrice;
  final String category; // vide = toutes
  /// Point de reprise : date de publication de la plus récente annonce vue.
  final DateTime? checkpoint;
  final DateTime? lastLoadedAt;

  RadarSearch({
    this.id,
    required this.name,
    required this.url,
    this.active = true,
    this.maxPrice = 200,
    this.category = '16',
    this.checkpoint,
    this.lastLoadedAt,
  });

  factory RadarSearch.fromRow(Map<String, Object?> r) => RadarSearch(
        id: r['id'] as int,
        name: r['name'] as String,
        url: r['url'] as String,
        active: (r['active'] as int) == 1,
        maxPrice: (r['max_price'] as num).toDouble(),
        category: (r['category'] as String?) ?? '',
        checkpoint: _date(r['checkpoint']),
        lastLoadedAt: _date(r['last_loaded_at']),
      );

  Map<String, Object?> toRow() => {
        'name': name,
        'url': url,
        'active': active ? 1 : 0,
        'max_price': maxPrice,
        'category': category,
      };

  RadarSearch copyWith({String? name, String? url, bool? active, double? maxPrice, String? category}) =>
      RadarSearch(
        id: id,
        name: name ?? this.name,
        url: url ?? this.url,
        active: active ?? this.active,
        maxPrice: maxPrice ?? this.maxPrice,
        category: category ?? this.category,
        checkpoint: checkpoint,
        lastLoadedAt: lastLoadedAt,
      );
}

DateTime? _date(Object? ms) => ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms as int);

/// Annonce analysée par le radar (fil « Radar »).
class RadarAnalysis {
  final String listId;
  final int searchId;
  final String searchName;
  final String title;
  final double? price;
  final String url;
  final DateTime? publishedAt;
  final String stage; // pre | full | limit
  final double? margin;
  final bool profitable;
  final DateTime createdAt;
  final String entryJson;

  RadarAnalysis.fromRow(Map<String, Object?> r)
      : listId = r['list_id'] as String,
        searchId = (r['search_id'] as int?) ?? 0,
        searchName = (r['search_name'] as String?) ?? '',
        title = (r['title'] as String?) ?? '',
        price = (r['price'] as num?)?.toDouble(),
        url = (r['url'] as String?) ?? '',
        publishedAt = _date(r['published_at']),
        stage = (r['stage'] as String?) ?? 'pre',
        margin = (r['margin'] as num?)?.toDouble(),
        profitable = (r['profitable'] as int? ?? 0) == 1,
        createdAt = _date(r['created_at']) ?? DateTime.now(),
        entryJson = (r['entry'] as String?) ?? '{}';

  HistoryEntry get entry =>
      HistoryEntry.fromJson(Map<String, dynamic>.from(jsonDecode(entryJson) as Map));
}

/// Annonce vue par le radar (analysée ou non).
class SeenAd {
  final String listId;
  final int searchId;
  final DateTime seenAt;
  final String title;
  final double? price;
  final String url;
  final DateTime? publishedAt;
  final String reason;
  SeenAd.fromRow(Map<String, Object?> r)
      : listId = r['list_id'] as String,
        searchId = (r['search_id'] as int?) ?? 0,
        seenAt = _date(r['seen_at']) ?? DateTime.now(),
        title = (r['title'] as String?) ?? '',
        price = (r['price'] as num?)?.toDouble(),
        url = (r['url'] as String?) ?? '',
        publishedAt = _date(r['published_at']),
        reason = (r['reason'] as String?) ?? '';
}

class RadarNotifRow {
  final int id;
  final DateTime at;
  final String title;
  final String text;
  final String pkg;
  final int? searchId;
  RadarNotifRow.fromRow(Map<String, Object?> r)
      : id = r['id'] as int,
        at = _date(r['at'])!,
        title = (r['title'] as String?) ?? '',
        text = (r['text'] as String?) ?? '',
        pkg = (r['pkg'] as String?) ?? '',
        searchId = r['search_id'] as int?;
}

class RadarLogRow {
  final DateTime at;
  final String msg;
  RadarLogRow.fromRow(Map<String, Object?> r)
      : at = _date(r['at'])!,
        msg = (r['msg'] as String?) ?? '';
}

/// État du radar.
enum RadarState { active, paused, verify, off }

/// Mes achats-reventes (suivi du bénéfice réel).
const _dealsTable = '''CREATE TABLE deals(
  id INTEGER PRIMARY KEY AUTOINCREMENT, entry_id TEXT, title TEXT, url TEXT,
  bought_price REAL, bought_at INTEGER, estimated REAL, sold_price REAL, sold_at INTEGER,
  sold_where TEXT, note TEXT, entry TEXT, status TEXT, fees REAL, received_condition TEXT,
  items TEXT, mpb_quote REAL, list_id TEXT)''';

/// Colonnes ajoutées en v5 (onglet Stock).
const _dealsV5 = ['status TEXT', 'fees REAL', 'received_condition TEXT', 'items TEXT', 'mpb_quote REAL', 'list_id TEXT'];

/// Messages aux vendeurs (envois, file d'attente, test à blanc).
const messagesTable = '''CREATE TABLE messages(
  id INTEGER PRIMARY KEY AUTOINCREMENT, list_id TEXT, url TEXT, title TEXT, seller TEXT,
  offer REAL, text TEXT, status TEXT, step TEXT, error TEXT, auto INTEGER,
  created_at INTEGER, not_before INTEGER, sent_at INTEGER, reply TEXT, replied_at INTEGER)''';

/// Stockage sqflite du radar (partagé par l'appli et le service en arrière-plan).
class RadarDb {
  static Database? _db;

  static Future<Database> get db async {
    if (_db != null) return _db!;
    final path = p.join(await getDatabasesPath(), 'radar.db');
    _db = await openDatabase(path, version: 5, onUpgrade: (d, from, to) async {
      if (from < 2) {
        for (final c in ['title TEXT', 'price REAL', 'url TEXT', 'published_at INTEGER', 'reason TEXT']) {
          await d.execute('ALTER TABLE seen_ads ADD COLUMN $c');
        }
      }
      if (from < 3) await d.execute(_dealsTable);
      if (from < 4) await d.execute(messagesTable);
      if (from >= 3 && from < 5) {
        for (final c in _dealsV5) {
          await d.execute('ALTER TABLE deals ADD COLUMN $c');
        }
      }
      if (from >= 4 && from < 5) {
        await d.execute('ALTER TABLE messages ADD COLUMN reply TEXT');
        await d.execute('ALTER TABLE messages ADD COLUMN replied_at INTEGER');
      }
    }, onCreate: (d, _) async {
      await d.execute(_dealsTable);
      await d.execute(messagesTable);
      await d.execute('''CREATE TABLE searches(
        id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, url TEXT, active INTEGER,
        max_price REAL, category TEXT, checkpoint INTEGER, last_loaded_at INTEGER,
        created_at INTEGER)''');
      await d.execute('''CREATE TABLE seen_ads(
        list_id TEXT PRIMARY KEY, search_id INTEGER, seen_at INTEGER, title TEXT, price REAL,
        url TEXT, published_at INTEGER, reason TEXT)''');
      await d.execute('''CREATE TABLE analyses(
        list_id TEXT PRIMARY KEY, search_id INTEGER, search_name TEXT, title TEXT,
        price REAL, url TEXT, published_at INTEGER, stage TEXT, margin REAL,
        profitable INTEGER, entry TEXT, created_at INTEGER)''');
      await d.execute('''CREATE TABLE notifs(
        id INTEGER PRIMARY KEY AUTOINCREMENT, at INTEGER, title TEXT, text TEXT,
        pkg TEXT, search_id INTEGER)''');
      await d.execute('CREATE TABLE logs(id INTEGER PRIMARY KEY AUTOINCREMENT, at INTEGER, msg TEXT)');
      await d.execute('CREATE TABLE kv(k TEXT PRIMARY KEY, v TEXT)');
      await d.execute('CREATE TABLE page_loads(at INTEGER, kind TEXT)');
    });
    return _db!;
  }

  static int _now() => DateTime.now().millisecondsSinceEpoch;

  // ---------------------------------------------------------------- recherches

  static Future<List<RadarSearch>> searches() async =>
      (await (await db).query('searches', orderBy: 'id')).map(RadarSearch.fromRow).toList();

  static Future<int> saveSearch(RadarSearch s) async {
    final d = await db;
    if (s.id == null) {
      return d.insert('searches', {...s.toRow(), 'created_at': _now()});
    }
    await d.update('searches', s.toRow(), where: 'id = ?', whereArgs: [s.id]);
    return s.id!;
  }

  static Future<void> deleteSearch(int id) async =>
      (await db).delete('searches', where: 'id = ?', whereArgs: [id]);

  static Future<void> setCheckpoint(int id, DateTime? checkpoint) async => (await db).update(
      'searches', {'checkpoint': checkpoint?.millisecondsSinceEpoch, 'last_loaded_at': _now()},
      where: 'id = ?', whereArgs: [id]);

  static Future<void> resetCheckpoint(int id) async =>
      (await db).update('searches', {'checkpoint': null}, where: 'id = ?', whereArgs: [id]);

  // -------------------------------------------------------------- annonces vues

  static Future<Set<String>> seenAmong(List<String> ids) async {
    if (ids.isEmpty) return {};
    final rows = await (await db).query('seen_ads',
        columns: ['list_id'], where: 'list_id IN (${List.filled(ids.length, '?').join(',')})', whereArgs: ids);
    return rows.map((r) => r['list_id'] as String).toSet();
  }

  static Future<void> markSeen(int searchId, Iterable<String> ids) async {
    final b = (await db).batch();
    for (final id in ids) {
      b.insert('seen_ads', {'list_id': id, 'search_id': searchId, 'seen_at': _now()},
          conflictAlgorithm: ConflictAlgorithm.ignore);
    }
    await b.commit(noResult: true);
  }

  /// Annonce vue avec son titre, son prix et ce que le radar en a fait.
  static Future<void> markSeenAd(int searchId, String listId,
      {required String title, double? price, String url = '', DateTime? publishedAt, required String reason}) async {
    await (await db).insert(
        'seen_ads',
        {
          'list_id': listId,
          'search_id': searchId,
          'seen_at': _now(),
          'title': title,
          'price': price,
          'url': url,
          'published_at': publishedAt?.millisecondsSinceEpoch,
          'reason': reason,
        },
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Toutes les annonces vues (les plus récentes d'abord), avec la raison.
  static Future<List<SeenAd>> seenAds({int? searchId, int limit = 1000}) async =>
      (await (await db).query('seen_ads',
              where: searchId == null ? null : 'search_id = ?',
              whereArgs: searchId == null ? null : [searchId],
              orderBy: 'seen_at DESC',
              limit: limit))
          .map(SeenAd.fromRow)
          .toList();

  // ------------------------------------------------------------------ analyses

  static Future<void> saveAnalysis({
    required String listId,
    required RadarSearch search,
    required String title,
    required double? price,
    required String url,
    required DateTime? publishedAt,
    required String stage,
    required double? margin,
    required bool profitable,
    required HistoryEntry entry,
  }) async {
    await (await db).insert(
        'analyses',
        {
          'list_id': listId,
          'search_id': search.id,
          'search_name': search.name,
          'title': title,
          'price': price,
          'url': url,
          'published_at': publishedAt?.millisecondsSinceEpoch,
          'stage': stage,
          'margin': margin,
          'profitable': profitable ? 1 : 0,
          'entry': jsonEncode(entry.toJson()),
          'created_at': _now(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Fil : « recent » (les plus récentes d'abord) ou « best » (meilleures
  /// marges d'abord, non chiffrées à la fin).
  static Future<List<RadarAnalysis>> analyses({int? searchId, int limit = 5000, String sort = 'recent'}) async =>
      (await (await db).query('analyses',
              where: searchId == null ? null : 'search_id = ?',
              whereArgs: searchId == null ? null : [searchId],
              orderBy: sort == 'best'
                  ? 'margin IS NULL, margin DESC, created_at DESC'
                  : 'created_at DESC',
              limit: limit))
          .map(RadarAnalysis.fromRow)
          .toList();

  static Future<void> deleteAnalysis(String listId) async =>
      (await db).delete('analyses', where: 'list_id = ?', whereArgs: [listId]);

  /// Supprime des analyses (par identifiant d'annonce) et rend leur nombre.
  /// [forgetSeen] : oublie aussi ces annonces (le radar pourra les ré-analyser) ;
  /// sinon elles restent « vues » (raison : analyse supprimée), donc pas de ré-analyse.
  static Future<int> deleteAnalyses(Iterable<String> listIds, {bool forgetSeen = false}) async {
    final ids = listIds.toSet().toList();
    if (ids.isEmpty) return 0;
    var removed = 0;
    await (await db).transaction((tx) async {
      for (var i = 0; i < ids.length; i += 500) {
        final end = i + 500 > ids.length ? ids.length : i + 500;
        final chunk = ids.sublist(i, end);
        final ph = List.filled(chunk.length, '?').join(',');
        removed += await tx.delete('analyses', where: 'list_id IN ($ph)', whereArgs: chunk);
        if (forgetSeen) {
          await tx.delete('seen_ads', where: 'list_id IN ($ph)', whereArgs: chunk);
        } else {
          await tx.update('seen_ads', {'reason': 'analyse supprimée'},
              where: 'list_id IN ($ph)', whereArgs: chunk);
        }
      }
    });
    return removed;
  }

  /// Supprime toutes les analyses (ou celles d'une seule recherche) et rend leur nombre.
  static Future<int> deleteAllAnalyses({int? searchId, bool forgetSeen = false}) async {
    final rows = await (await db).query('analyses',
        columns: ['list_id'],
        where: searchId == null ? null : 'search_id = ?',
        whereArgs: searchId == null ? null : [searchId]);
    return deleteAnalyses(rows.map((r) => r['list_id'] as String), forgetSeen: forgetSeen);
  }

  static Future<RadarAnalysis?> analysis(String listId) async {
    final rows = await (await db).query('analyses', where: 'list_id = ?', whereArgs: [listId]);
    return rows.isEmpty ? null : RadarAnalysis.fromRow(rows.first);
  }

  static Future<void> updateEntry(String listId, HistoryEntry e, {double? minMargin}) async {
    final m = e.analysis.margin;
    await (await db).update(
        'analyses',
        {
          'entry': jsonEncode(e.toJson()),
          if (minMargin != null) 'margin': m,
          if (minMargin != null) 'profitable': m != null && m >= minMargin ? 1 : 0,
        },
        where: 'list_id = ?',
        whereArgs: [listId]);
  }

  static Future<({int seen, int analyzed, RadarAnalysis? best})> today() async {
    final d = await db;
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day).millisecondsSinceEpoch;
    final seen = Sqflite.firstIntValue(
            await d.rawQuery('SELECT COUNT(*) FROM seen_ads WHERE seen_at >= ?', [start])) ??
        0;
    final analyzed = Sqflite.firstIntValue(
            await d.rawQuery('SELECT COUNT(*) FROM analyses WHERE created_at >= ?', [start])) ??
        0;
    final best = await d.query('analyses',
        where: 'created_at >= ? AND margin IS NOT NULL', whereArgs: [start], orderBy: 'margin DESC', limit: 1);
    return (seen: seen, analyzed: analyzed, best: best.isEmpty ? null : RadarAnalysis.fromRow(best.first));
  }

  // ------------------------------------------------------- notifications reçues

  static Future<void> addNotif(String title, String text, String pkg, int? searchId, DateTime at) async {
    final d = await db;
    await d.insert('notifs', {
      'at': at.millisecondsSinceEpoch,
      'title': title,
      'text': text,
      'pkg': pkg,
      'search_id': searchId,
    });
    await d.rawDelete('DELETE FROM notifs WHERE id NOT IN (SELECT id FROM notifs ORDER BY id DESC LIMIT 200)');
  }

  static Future<List<RadarNotifRow>> notifs() async =>
      (await (await db).query('notifs', orderBy: 'id DESC', limit: 200)).map(RadarNotifRow.fromRow).toList();

  // --------------------------------------------------------------------- journal

  static Future<void> log(String msg) async {
    final d = await db;
    await d.insert('logs', {'at': _now(), 'msg': msg});
    await d.rawDelete('DELETE FROM logs WHERE id NOT IN (SELECT id FROM logs ORDER BY id DESC LIMIT 1000)');
  }

  static Future<List<RadarLogRow>> logs({int limit = 500}) async =>
      (await (await db).query('logs', orderBy: 'id DESC', limit: limit)).map(RadarLogRow.fromRow).toList();

  static Future<void> clearLogs() async => (await db).delete('logs');

  // ------------------------------------------------------------- clé / valeur

  static Future<String?> get(String k) async {
    final rows = await (await db).query('kv', where: 'k = ?', whereArgs: [k]);
    return rows.isEmpty ? null : rows.first['v'] as String?;
  }

  static Future<void> set(String k, String? v) async {
    final d = await db;
    if (v == null) {
      await d.delete('kv', where: 'k = ?', whereArgs: [k]);
    } else {
      await d.insert('kv', {'k': k, 'v': v}, conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }

  /// Tri du fil choisi par l'utilisateur (« recent » ou « best »).
  static Future<String> feedSort() async => await get('feed_sort') ?? 'recent';
  static Future<void> setFeedSort(String v) => set('feed_sort', v);

  static Future<int> getInt(String k) async => int.tryParse(await get(k) ?? '') ?? 0;
  static Future<void> setInt(String k, int v) => set(k, '$v');

  static Future<RadarState> state() async {
    final s = await get('state');
    if (s == 'verify') return RadarState.verify;
    if (await getInt('paused_until') > _now()) return RadarState.paused;
    return RadarState.active;
  }

  // ----------------------------------------------------------- limites de débit

  static Future<void> addPageLoad(String kind) async =>
      (await db).insert('page_loads', {'at': _now(), 'kind': kind});

  static Future<int> pageLoadsLastHour(String kind) async {
    final d = await db;
    final since = _now() - 3600 * 1000;
    await d.delete('page_loads', where: 'at < ?', whereArgs: [since - 3600 * 1000]);
    return Sqflite.firstIntValue(await d.rawQuery(
            'SELECT COUNT(*) FROM page_loads WHERE kind = ? AND at >= ?', [kind, since])) ??
        0;
  }

  static Future<DateTime?> lastPageLoad() async {
    final v = Sqflite.firstIntValue(await (await db).rawQuery('SELECT MAX(at) FROM page_loads'));
    return v == null ? null : DateTime.fromMillisecondsSinceEpoch(v);
  }
}
