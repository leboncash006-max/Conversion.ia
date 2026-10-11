import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../radar/radar_bridge.dart';
import '../services/deepseek_web.dart';

/// Connexion à DeepSeek dans une WebView visible, directement sur le CHAT
/// (https://chat.deepseek.com/, pas le site vitrine www.deepseek.com). Je tape
/// moi-même mes identifiants (et passe la vérification si on me la demande) :
/// l'appli ne lit jamais le mot de passe, seuls les cookies de session sont
/// conservés et réutilisés par la WebView invisible.
class DeepSeekLoginScreen extends StatefulWidget {
  const DeepSeekLoginScreen({super.key});

  @override
  State<DeepSeekLoginScreen> createState() => _DeepSeekLoginScreenState();
}

class _DeepSeekLoginScreenState extends State<DeepSeekLoginScreen> {
  late final WebViewController _web = WebViewController()
    ..setJavaScriptMode(JavaScriptMode.unrestricted)
    ..setNavigationDelegate(NavigationDelegate(
      onProgress: (p) {
        if (mounted) setState(() => _progress = p);
      },
      onNavigationRequest: (r) {
        if (!r.url.startsWith('http')) return NavigationDecision.prevent;
        // le site vitrine (www.deepseek.com/en/…) n'est pas le chat : on y retourne
        final host = Uri.tryParse(r.url)?.host ?? '';
        if (DsSite.isMarketingHost(host)) {
          _web.loadRequest(Uri.parse(DsSite.url));
          return NavigationDecision.prevent;
        }
        return NavigationDecision.navigate;
      },
    ))
    ..loadRequest(Uri.parse(DsSite.url));
  int _progress = 0;

  /// Vérifie dans la page qu'on est bien sur le chat, avec la zone de saisie.
  Future<bool> _connected() async {
    try {
      final r = await _web.runJavaScriptReturningResult(
          "(location.host + '|' + (document.querySelector(${_q(DsSite.input)}) ? 'input' : 'none'))");
      final s = r.toString().replaceAll('"', '');
      return s.startsWith(DsSite.chatHost) && s.endsWith('|input');
    } catch (_) {
      return false;
    }
  }

  String _q(String s) => "'${s.replaceAll("'", "\\'")}'";

  Future<void> _done() async {
    final ok = await _connected();
    await RadarBridge.flushCookies();
    DeepSeekWeb.resume();
    if (!mounted) return;
    if (ok) {
      Navigator.pop(context, true);
      return;
    }
    // pas (encore) sur la zone de discussion : on prévient, sans bloquer
    final leave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Pas encore connecté ?'),
        content: const Text(
            'Je ne vois pas la zone de discussion de DeepSeek. Termine la connexion '
            '(jusqu\'à pouvoir écrire un message), puis appuie de nouveau sur « Terminé ».'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Quitter quand même')),
          FilledButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Continuer')),
        ],
      ),
    );
    if (leave == true && mounted) Navigator.pop(context, false);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          RadarBridge.flushCookies();
          DeepSeekWeb.resume();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Connexion DeepSeek'),
          actions: [
            IconButton(tooltip: 'Recharger', icon: const Icon(Icons.refresh), onPressed: () => _web.reload()),
            IconButton(
                tooltip: 'Aller au chat',
                icon: const Icon(Icons.forum_outlined),
                onPressed: () => _web.loadRequest(Uri.parse(DsSite.url))),
            TextButton(onPressed: _done, child: const Text('Terminé')),
          ],
          bottom: _progress < 100
              ? PreferredSize(
                  preferredSize: const Size.fromHeight(3),
                  child: LinearProgressIndicator(value: _progress / 100, minHeight: 3))
              : null,
        ),
        body: Column(children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            color: Theme.of(context).colorScheme.surfaceContainerHigh,
            child: const Text(
              'Connecte-toi à chat.deepseek.com (et fais toi-même la vérification si on te la demande), '
              'jusqu\'à voir la zone pour écrire un message. Appuie ensuite sur « Terminé ». '
              'L\'appli ne lit pas ton mot de passe : seule la session reste ouverte.',
              style: TextStyle(fontSize: 12.5),
            ),
          ),
          Expanded(child: WebViewWidget(controller: _web)),
        ]),
      ),
    );
  }
}
