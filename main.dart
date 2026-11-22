import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';

const teal = Color(0xFF0F4C45);
final dark = ValueNotifier<bool>(false);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  dark.value = (await SharedPreferences.getInstance()).getBool('dark') ?? false;
  runApp(const ApsApp());
}

class ApsApp extends StatelessWidget {
  const ApsApp({super.key});
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
        valueListenable: dark,
        builder: (_, d, __) => MaterialApp(
          title: 'APS',
          debugShowCheckedModeBanner: false,
          themeMode: d ? ThemeMode.dark : ThemeMode.light,
          theme: ThemeData(colorSchemeSeed: teal, useMaterial3: true),
          darkTheme: ThemeData(colorSchemeSeed: teal, useMaterial3: true, brightness: Brightness.dark),
          home: const Home(),
        ),
      );
}

void toast(BuildContext c, String m) =>
    ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(m)));

class Home extends StatefulWidget {
  const Home({super.key});
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  List<List<String>> items = [];
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    setState(() => items = (p.getStringList('recent') ?? [])
        .map((e) => e.split('\u0001'))
        .where((e) => e.length == 3)
        .toList());
  }

  Future<void> open(String title, String src, bool url) async {
    if (!url && !File(src).existsSync()) return toast(context, 'File not found');
    final p = await SharedPreferences.getInstance();
    final l = p.getStringList('recent') ?? [];
    final e = [title, src, url ? '1' : '0'].join('\u0001');
    l.remove(e);
    l.insert(0, e);
    await p.setStringList('recent', l.take(30).toList());
    if (!mounted) return;
    await Navigator.push(context, MaterialPageRoute(builder: (_) => Reader(title: title, src: src, url: url)));
    load();
  }

  Future<void> pick() async {
    final r = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['pdf']);
    final f = r?.files.single;
    if (f?.path == null) return;
    final dir = await getApplicationDocumentsDirectory();
    final copy = await File(f!.path!).copy('${dir.path}/${f.name}');
    open(f.name, copy.path, false);
  }

  Future<void> openLink() async {
    final t = TextEditingController();
    final u = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Open PDF link'),
        content: TextField(controller: t, autofocus: true, keyboardType: TextInputType.url, decoration: const InputDecoration(hintText: 'https://...pdf')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, t.text.trim()), child: const Text('Open')),
        ],
      ),
    );
    if (u == null || !u.startsWith('http')) return;
    final seg = Uri.parse(u).pathSegments;
    open(seg.isNotEmpty && seg.last.isNotEmpty ? seg.last : u, u, true);
  }

  Future<void> remove(List<String> e) async {
    final p = await SharedPreferences.getInstance();
    final l = p.getStringList('recent') ?? [];
    l.remove(e.join('\u0001'));
    await p.setStringList('recent', l);
    load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('APS', style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1)),
          actions: [
            IconButton(icon: const Icon(Icons.link), tooltip: 'Open link', onPressed: openLink),
            IconButton(
              icon: const Icon(Icons.info_outline),
              tooltip: 'About',
              onPressed: () => showAboutDialog(
                context: context,
                applicationName: 'APS',
                applicationVersion: 'Version 3.35',
                applicationIcon: ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.asset('assets/icon.png', width: 48, height: 48)),
                applicationLegalese: 'Published by Mejba Limited\n© Mejba Limited',
              ),
            ),
            IconButton(
              icon: Icon(dark.value ? Icons.light_mode : Icons.dark_mode),
              tooltip: 'Dark mode',
              onPressed: () async {
                dark.value = !dark.value;
                (await SharedPreferences.getInstance()).setBool('dark', dark.value);
                setState(() {});
              },
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(onPressed: pick, icon: const Icon(Icons.folder_open), label: const Text('Open PDF')),
        body: items.isEmpty
            ? const Center(child: Text('No recent files.\nTap Open PDF or the link icon.', textAlign: TextAlign.center))
            : ListView(
                children: [
                  for (final e in items)
                    ListTile(
                      leading: Icon(e[2] == '1' ? Icons.cloud_outlined : Icons.picture_as_pdf, color: const Color(0xFFF2A93B)),
                      title: Text(e[0], maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: e[2] == '1' ? Text(e[1], maxLines: 1, overflow: TextOverflow.ellipsis) : null,
                      trailing: IconButton(icon: const Icon(Icons.close), onPressed: () => remove(e)),
                      onTap: () => open(e[0], e[1], e[2] == '1'),
                    ),
                ],
              ),
      );
}

class Reader extends StatefulWidget {
  final String title, src;
  final bool url;
  const Reader({super.key, required this.title, required this.src, required this.url});
  @override
  State<Reader> createState() => _ReaderState();
}

class _ReaderState extends State<Reader> {
  final c = PdfViewerController();
  final q = TextEditingController();
  PdfTextSearchResult? res;
  bool searching = false, hl = false, night = false;
  int page = 1, total = 0;
  List<int> bms = [];
  String get bk => 'bm:${widget.src}';

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) => setState(() => bms = (p.getStringList(bk) ?? []).map(int.parse).toList()..sort()));
  }

  Future<void> saveBms() async {
    bms = bms.toSet().toList()..sort();
    (await SharedPreferences.getInstance()).setStringList(bk, bms.map((e) => '$e').toList());
    setState(() {});
  }

  Future<void> save() async {
    final bytes = await c.saveDocument();
    final base = (await getExternalStorageDirectory()) ?? await getApplicationDocumentsDirectory();
    var n = widget.title.replaceAll(RegExp(r'[^\w.\- ]'), '_');
    if (!n.toLowerCase().endsWith('.pdf')) n = '$n.pdf';
    final f = File('${base.path}/APS_$n');
    await f.writeAsBytes(bytes);
    if (mounted) toast(context, 'Saved: ${f.path}');
  }

  Future<void> jump() async {
    final t = TextEditingController();
    final n = await showDialog<int>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Go to page (1-$total)'),
        content: TextField(controller: t, autofocus: true, keyboardType: TextInputType.number),
        actions: [TextButton(onPressed: () => Navigator.pop(context, int.tryParse(t.text)), child: const Text('Go'))],
      ),
    );
    if (n != null && n >= 1 && n <= total) c.jumpToPage(n);
  }

  void showBms() => showModalBottomSheet(
        context: context,
        builder: (_) => StatefulBuilder(
          builder: (ctx, set) => bms.isEmpty
              ? const SizedBox(height: 120, child: Center(child: Text('No bookmarks yet')))
              : ListView(children: [
                  for (final b in bms)
                    ListTile(
                      leading: const Icon(Icons.bookmark, color: Color(0xFFF2A93B)),
                      title: Text('Page $b'),
                      onTap: () {
                        Navigator.pop(ctx);
                        c.jumpToPage(b);
                      },
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () async {
                          bms.remove(b);
                          await saveBms();
                          set(() {});
                        },
                      ),
                    ),
                ]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    void loaded(PdfDocumentLoadedDetails d) => setState(() => total = d.document.pages.count);
    void failed(PdfDocumentLoadFailedDetails d) => toast(context, d.description);
    void changed(PdfPageChangedDetails d) => setState(() => page = d.newPageNumber);
    final viewer = widget.url
        ? SfPdfViewer.network(widget.src, controller: c, onDocumentLoaded: loaded, onDocumentLoadFailed: failed, onPageChanged: changed)
        : SfPdfViewer.file(File(widget.src), controller: c, onDocumentLoaded: loaded, onDocumentLoadFailed: failed, onPageChanged: changed);
    final r = res;
    return Scaffold(
      appBar: AppBar(
        title: searching
            ? TextField(
                controller: q,
                autofocus: true,
                decoration: const InputDecoration(hintText: 'Search in PDF', border: InputBorder.none),
                textInputAction: TextInputAction.search,
                onSubmitted: (v) async {
                  res = await c.searchText(v);
                  setState(() {});
                },
              )
            : Text(widget.title, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            icon: Icon(searching ? Icons.close : Icons.search),
            onPressed: () => setState(() {
              searching = !searching;
              if (!searching) {
                res?.clear();
                res = null;
                q.clear();
              }
            }),
          ),
          IconButton(
            icon: Icon(Icons.border_color, color: hl ? const Color(0xFFF2A93B) : null),
            tooltip: 'Highlight',
            onPressed: () => setState(() {
              hl = !hl;
              c.annotationMode = hl ? PdfAnnotationMode.highlight : PdfAnnotationMode.none;
            }),
          ),
          PopupMenuButton<String>(
            onSelected: (v) async {
              switch (v) {
                case 'bm':
                  bms.add(page);
                  await saveBms();
                  if (mounted) toast(context, 'Bookmarked page $page');
                  break;
                case 'bms':
                  showBms();
                  break;
                case 'go':
                  jump();
                  break;
                case 'zi':
                  c.zoomLevel = (c.zoomLevel + 0.5).clamp(1.0, 3.0);
                  break;
                case 'zo':
                  c.zoomLevel = (c.zoomLevel - 0.5).clamp(1.0, 3.0);
                  break;
                case 'night':
                  setState(() => night = !night);
                  break;
                case 'save':
                  save();
                  break;
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'bm', child: Text('Add bookmark')),
              PopupMenuItem(value: 'bms', child: Text('Bookmarks')),
              PopupMenuItem(value: 'go', child: Text('Go to page')),
              PopupMenuItem(value: 'zi', child: Text('Zoom in')),
              PopupMenuItem(value: 'zo', child: Text('Zoom out')),
              PopupMenuItem(value: 'night', child: Text('Night reading')),
              PopupMenuItem(value: 'save', child: Text('Save copy')),
            ],
          ),
        ],
      ),
      body: night
          ? ColorFiltered(
              colorFilter: const ColorFilter.matrix([-1, 0, 0, 0, 255, 0, -1, 0, 0, 255, 0, 0, -1, 0, 255, 0, 0, 0, 1, 0]),
              child: viewer)
          : viewer,
      bottomNavigationBar: BottomAppBar(
        height: 52,
        child: r != null && r.hasResult
            ? Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                IconButton(icon: const Icon(Icons.keyboard_arrow_up), onPressed: () { r.previousInstance(); setState(() {}); }),
                Text('${r.currentInstanceIndex} / ${r.totalInstanceCount}'),
                IconButton(icon: const Icon(Icons.keyboard_arrow_down), onPressed: () { r.nextInstance(); setState(() {}); }),
              ])
            : Center(child: Text('Page $page / $total')),
      ),
    );
  }
}
